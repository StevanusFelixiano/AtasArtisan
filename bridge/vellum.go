package main

// Vellum additions on top of whatsapp-mcp-plus: the Mac app launches one bridge per
// linked number, talks to it over 127.0.0.1 with a per-launch token, and reads
// everything WhatsApp tells us from one SSE stream.

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"sort"
	"strconv"
	"sync"
	"time"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
)

// storeDir holds whatsapp.db (the session) and messages.db. Set by -store.
var storeDir = "store"

// hub fans bridge events out to every /api/events subscriber.
type hub struct {
	mu    sync.Mutex
	subs  map[chan []byte]struct{}
	state []byte // last login-state event, replayed to each new subscriber
}

var bus = &hub{subs: map[chan []byte]struct{}{}}

func (h *hub) emit(kind string, data any) {
	b, _ := json.Marshal(map[string]any{"kind": kind, "data": data})
	h.mu.Lock()
	defer h.mu.Unlock()
	switch kind {
	case "qr", "pair_code", "connected", "logged_out":
		h.state = b
	}
	for c := range h.subs {
		select {
		case c <- b:
		default: // ponytail: a stalled subscriber drops events; it catches up through /api/messages
		}
	}
}

func (h *hub) serve(w http.ResponseWriter, r *http.Request) {
	fl, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming unsupported", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	c := make(chan []byte, 256)
	h.mu.Lock()
	h.subs[c] = struct{}{}
	state := h.state
	h.mu.Unlock()
	defer func() { h.mu.Lock(); delete(h.subs, c); h.mu.Unlock() }()

	if state != nil {
		fmt.Fprintf(w, "data: %s\n\n", state)
	}
	fl.Flush()
	ping := time.NewTicker(15 * time.Second)
	defer ping.Stop()
	for {
		select {
		case <-r.Context().Done():
			return
		case b := <-c:
			fmt.Fprintf(w, "data: %s\n\n", b)
			fl.Flush()
		case <-ping.C:
			fmt.Fprint(w, ": ping\n\n")
			fl.Flush()
		}
	}
}

// requireToken guards every route with ATASTE_BRIDGE_TOKEN when it is set. The bridge
// can send from the couple's number, so nothing else on the machine may reach it.
func requireToken(next http.Handler) http.Handler {
	token := os.Getenv("ATASTE_BRIDGE_TOKEN")
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if token != "" && subtle.ConstantTimeCompare([]byte(r.Header.Get("Authorization")), []byte("Bearer "+token)) != 1 {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// exitWithParent ends the bridge once the Mac app that launched it is gone, so a crashed app never
// leaves a bridge holding the port (and the couple's number) behind a token nobody knows any more.
func exitWithParent() {
	ppid := os.Getppid()
	for range time.Tick(2 * time.Second) {
		if os.Getppid() != ppid {
			os.Exit(0)
		}
	}
}

// phoneOf returns the phone number (digits only) behind a user JID, resolving a LID
// through the device's LID map. Empty when WhatsApp has not told us the number.
func phoneOf(client *whatsmeow.Client, jid types.JID) string {
	switch jid.Server {
	case types.DefaultUserServer:
		return jid.User
	case types.HiddenUserServer:
		if pn, err := client.Store.LIDs.GetPNForLID(context.Background(), jid); err == nil {
			return pn.User
		}
	}
	return ""
}

// messagePhone is the other party's number in a direct chat; empty for groups.
func messagePhone(client *whatsmeow.Client, info types.MessageInfo) string {
	if info.IsGroup {
		return ""
	}
	cands := []types.JID{info.Chat}
	if info.IsFromMe {
		cands = append(cands, info.RecipientAlt)
	} else {
		cands = append(cands, info.SenderAlt, info.Sender)
	}
	for _, j := range cands {
		if p := phoneOf(client, j); p != "" {
			return p
		}
	}
	return ""
}

type messageEvent struct {
	ID       string `json:"id"`
	Chat     string `json:"chat"`
	Phone    string `json:"phone"`
	FromMe   bool   `json:"from_me"`
	Text     string `json:"text"`
	Media    string `json:"media,omitempty"`
	QuotedID string `json:"quoted_id,omitempty"`
	PushName string `json:"push_name,omitempty"`
	TS       int64  `json:"ts"`
}

func emitMessage(client *whatsmeow.Client, msg *events.Message, content, mediaType string) {
	bus.emit("message", messageEvent{
		ID:       msg.Info.ID,
		Chat:     msg.Info.Chat.String(),
		Phone:    messagePhone(client, msg.Info),
		FromMe:   msg.Info.IsFromMe,
		Text:     content,
		Media:    mediaType,
		QuotedID: msg.Message.GetExtendedTextMessage().GetContextInfo().GetStanzaID(),
		PushName: msg.Info.PushName,
		TS:       msg.Info.Timestamp.Unix(),
	})
	go atasteHook(messagePhone(client, msg.Info), msg.Info, content)
}

// handleVellumEvent covers the events the original bridge ignored.
func handleVellumEvent(client *whatsmeow.Client, evt interface{}) {
	switch v := evt.(type) {
	case *events.Connected:
		if client.Store.ID != nil {
			bus.emit("connected", map[string]any{"phone": client.Store.ID.User, "push_name": client.Store.PushName})
		}
	case *events.LoggedOut:
		bus.emit("logged_out", map[string]any{"reason": v.Reason.String()})
		// whatsmeow has deleted this device's session; the same client can't pair again
		// ("invalid use of deleted device"). Exit and let systemd start fresh with a new device.
		go func() { time.Sleep(time.Second); os.Exit(3) }()
	case *events.Receipt:
		status := map[types.ReceiptType]string{types.ReceiptTypeDelivered: "delivered", types.ReceiptTypeRead: "read"}[v.Type]
		if status == "" || v.IsFromMe || v.IsGroup {
			return
		}
		bus.emit("receipt", map[string]any{
			"ids": v.MessageIDs, "chat": v.Chat.String(), "phone": phoneOf(client, v.Chat),
			"status": status, "ts": v.Timestamp.Unix(),
		})
	}
}

// pairLoop keeps a QR code on offer until a phone links. whatsmeow's QR channel runs dry
// after a few minutes, so each round reconnects for a fresh one.
// ponytail: a phone-number pairing code dies with the round it was issued in (~2.5 min);
// the couple asks for a new one. Hold the socket open across rounds if that bites.
func pairLoop(client *whatsmeow.Client) {
	for client.Store.ID == nil {
		qr, err := client.GetQRChannel(context.Background())
		if err == nil {
			err = client.Connect()
		}
		if err != nil {
			fmt.Printf("pairing: %v\n", err)
			time.Sleep(5 * time.Second)
			continue
		}
		for evt := range qr {
			switch evt.Event {
			case whatsmeow.QRChannelEventCode:
				bus.emit("qr", map[string]any{"code": evt.Code, "expires_in": int(evt.Timeout.Seconds())})
			case whatsmeow.QRChannelSuccess.Event:
				return // events.Connected reports the linked number
			}
		}
		client.Disconnect()
	}
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}

func registerVellumRoutes(client *whatsmeow.Client, store *MessageStore) {
	atasteClient, atasteStore = client, store
	http.HandleFunc("/api/events", bus.serve)

	http.HandleFunc("/api/login/pair", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Phone string `json:"phone"`
		}
		if !decodePost(w, r, &req) {
			return
		}
		code, err := client.PairPhone(r.Context(), req.Phone, true, whatsmeow.PairClientChrome, "Chrome (Mac OS)")
		if err != nil {
			writeGeneric(w, false, err.Error(), "")
			return
		}
		bus.emit("pair_code", map[string]any{"code": code, "phone": req.Phone})
		writeGeneric(w, true, "Enter the code in WhatsApp", code)
	})

	http.HandleFunc("/api/logout", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		if err := client.Logout(r.Context()); err != nil {
			writeGeneric(w, false, err.Error(), "")
			return
		}
		bus.emit("logged_out", map[string]any{"reason": "logged out from Vellum"})
		go pairLoop(client)
		writeGeneric(w, true, "Logged out", "")
	})

	// Joined groups and their people, for the "a WhatsApp group" import source.
	http.HandleFunc("/api/groups", func(w http.ResponseWriter, r *http.Request) {
		groups, err := client.GetJoinedGroups(r.Context())
		if err != nil {
			writeGeneric(w, false, err.Error(), "")
			return
		}
		type person struct {
			Phone string `json:"phone"`
			Name  string `json:"name,omitempty"`
		}
		type group struct {
			JID        string   `json:"jid"`
			Name       string   `json:"name"`
			People     []person `json:"people"`
			LastActive int64    `json:"last_active"`
		}
		// Newest conversation first: the group the couple is thinking of is usually the one that moved last.
		last := map[string]int64{}
		if rows, err := store.db.Query(`SELECT jid, last_message_time FROM chats WHERE jid LIKE '%@g.us'`); err == nil {
			for rows.Next() {
				var jid string
				var t time.Time
				if rows.Scan(&jid, &t) == nil {
					last[jid] = t.Unix()
				}
			}
			rows.Close()
		}
		me := ""
		if client.Store.ID != nil {
			me = client.Store.ID.User
		}
		out := make([]group, 0, len(groups))
		for _, g := range groups {
			gr := group{JID: g.JID.String(), Name: g.Name, LastActive: last[g.JID.String()]}
			for _, p := range g.Participants {
				phone := p.PhoneNumber.User
				if phone == "" {
					phone = phoneOf(client, p.JID)
				}
				if phone == "" || phone == me {
					continue
				}
				name := ""
				if c, err := client.Store.Contacts.GetContact(r.Context(), p.JID); err == nil {
					name = c.FullName
					if name == "" {
						name = c.PushName
					}
				}
				gr.People = append(gr.People, person{Phone: phone, Name: name})
			}
			out = append(out, gr)
		}
		sort.SliceStable(out, func(i, j int) bool { return out[i].LastActive > out[j].LastActive })
		writeJSON(w, out)
	})

	// Which numbers can be reached on WhatsApp at all ("landline only", "can't reach").
	http.HandleFunc("/api/check", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Phones []string `json:"phones"`
		}
		if !decodePost(w, r, &req) {
			return
		}
		res, err := client.IsOnWhatsApp(r.Context(), req.Phones)
		if err != nil {
			writeGeneric(w, false, err.Error(), "")
			return
		}
		type row struct {
			Phone      string `json:"phone"`
			OnWhatsApp bool   `json:"on_whatsapp"`
		}
		out := make([]row, 0, len(res))
		for _, x := range res {
			out = append(out, row{Phone: x.Query, OnWhatsApp: x.IsIn})
		}
		writeJSON(w, out)
	})

	// Catch-up for a subscriber that was away: direct-chat messages newer than ?since=<unix>.
	http.HandleFunc("/api/messages", func(w http.ResponseWriter, r *http.Request) {
		since, _ := strconv.ParseInt(r.URL.Query().Get("since"), 10, 64)
		rows, err := store.db.Query(`SELECT id, chat_jid, content, timestamp, is_from_me, COALESCE(media_type, '')
			FROM messages WHERE chat_jid NOT LIKE '%@g.us' AND timestamp > ? ORDER BY timestamp LIMIT 500`,
			time.Unix(since, 0))
		if err != nil {
			writeGeneric(w, false, err.Error(), "")
			return
		}
		defer rows.Close()
		out := []messageEvent{}
		for rows.Next() {
			var m messageEvent
			var ts time.Time
			if rows.Scan(&m.ID, &m.Chat, &m.Text, &ts, &m.FromMe, &m.Media) != nil {
				continue
			}
			m.TS = ts.Unix()
			if jid, err := types.ParseJID(m.Chat); err == nil {
				m.Phone = phoneOf(client, jid)
			}
			out = append(out, m)
		}
		writeJSON(w, out)
	})

	// How often the couple messages each number over the past year: the circle suggestion.
	http.HandleFunc("/api/chatstats", func(w http.ResponseWriter, r *http.Request) {
		rows, err := store.db.Query(`SELECT chat_jid, COUNT(*) FROM messages
			WHERE chat_jid NOT LIKE '%@g.us' AND timestamp > ? GROUP BY chat_jid`,
			time.Now().AddDate(-1, 0, 0))
		if err != nil {
			writeGeneric(w, false, err.Error(), "")
			return
		}
		defer rows.Close()
		counts := map[string]int{} // a person can have both a LID chat and a number chat
		for rows.Next() {
			var chat string
			var n int
			if rows.Scan(&chat, &n) != nil {
				continue
			}
			if jid, err := types.ParseJID(chat); err == nil {
				if p := phoneOf(client, jid); p != "" {
					counts[p] += n
				}
			}
		}
		writeJSON(w, counts)
	})
}
