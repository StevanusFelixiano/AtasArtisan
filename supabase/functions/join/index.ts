// https://<project>.supabase.co/functions/v1/join/<CODE> -> ataste://join/<CODE>
// Supabase can't host /.well-known for universal links, so the shared link bounces into the
// app's URL scheme (GoodMinton's pattern). The share text carries the TestFlight link for people
// without the app.
Deno.serve((req) => {
  const code = new URL(req.url).pathname.split("/").pop() ?? "";
  if (!/^[A-Za-z0-9]{6}$/.test(code)) return new Response("This Ataste link isn't valid.", { status: 404 });
  return new Response(null, { status: 302, headers: { location: `ataste://join/${code.toUpperCase()}` } });
});
