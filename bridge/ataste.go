package main

// Ataste reverse-OTP hook. A user taps "Continue with WhatsApp" in the app, WhatsApp opens
// with "ATASTE 4K9X" and a line of explanation typed, they press send. This file sees that message arrive, reads the
// sender's number, and reports {code, phone} to the Supabase `wa-inbound` function, which
// signs the waiting app in. The number is read from the message itself; the user never types it.

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"os"
	"regexp"
	"strings"
	"sync"
	"time"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/types"
)

var (
	atasteClient *whatsmeow.Client
	atasteStore  *MessageStore
	codeRe       = regexp.MustCompile(`\bATASTE\s+([A-Z0-9]{4})\b`) // anywhere in the message; builds before 13 send the bare code
	replyMu      sync.Mutex                                         // one reply at a time, spaced out: protects the number from looking like a bot
	httpc        = &http.Client{Timeout: 15 * time.Second}
)

type inboundReply struct {
	Status string `json:"status"` // verified | duplicate | expired | unknown
}

func atasteHook(phone string, info types.MessageInfo, text string) {
	if info.IsFromMe || info.IsGroup || atasteClient == nil {
		return
	}
	m := codeRe.FindStringSubmatch(text)
	if m == nil {
		return
	}
	// Old messages replayed after a long outage: the code is long expired, don't answer them.
	if time.Since(info.Timestamp) > 30*time.Minute {
		return
	}
	code := strings.ToUpper(m[1])
	// Blue ticks at once, before the backend round trip: testers who saw nothing for several seconds
	// re-sent the code. No "got it" reply: an automatic answer to every new contact gets the number flagged.
	if err := atasteClient.MarkRead(context.Background(), []types.MessageID{info.ID}, time.Now(), info.Chat, info.Sender); err != nil {
		fmt.Printf("ataste: mark read %s: %v\n", code, err)
	}
	if phone == "" {
		// A LID sender whose number WhatsApp hasn't shared with us yet. Never verify a LID.
		reply(info.Chat, "Sorry, we couldn't read your number from this chat. Please go back to Ataste and tap \"Send again\".")
		return
	}
	status, err := report(code, phone, info.ID, info.PushName)
	if err != nil {
		fmt.Printf("ataste: report %s: %v\n", code, err)
		reply(info.Chat, "Something went wrong on our side. Please try again in a minute.")
		return
	}
	// verified: the app signs in, no reply. duplicate: already answered once, stay quiet.
	if status == "expired" || status == "unknown" {
		reply(info.Chat, "This code has expired. Go back to Ataste and tap \"Send again\" for a new one.")
	}
}

func report(code, phone, waID, pushName string) (string, error) {
	body, _ := json.Marshal(map[string]string{"code": code, "phone": phone, "wa_id": waID, "push_name": pushName})
	req, err := http.NewRequest("POST", os.Getenv("ATASTE_INBOUND_URL"), bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-bridge-secret", os.Getenv("ATASTE_BRIDGE_SECRET"))
	resp, err := httpc.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("status %d", resp.StatusCode)
	}
	var r inboundReply
	if err := json.NewDecoder(resp.Body).Decode(&r); err != nil {
		return "", err
	}
	return r.Status, nil
}

// reply spaces each answer 2-5 s out.
func reply(chat types.JID, text string) {
	replyMu.Lock()
	defer replyMu.Unlock()
	time.Sleep(time.Duration(2000+rand.Intn(3000)) * time.Millisecond)
	if ok, msg, _ := sendWhatsAppMessage(atasteClient, atasteStore, chat.String(), text, "", ""); !ok {
		fmt.Printf("ataste: reply to %s failed: %s\n", chat, msg)
	}
}
