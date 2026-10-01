// https://<project>.supabase.co/functions/v1/join/<CODE>: links shared before 2026-10-01. Supabase can't serve
// HTML or /.well-known, so invites now live on the VPS page (repo web/, design 2-7); old links go there.
Deno.serve((req) => {
  const code = new URL(req.url).pathname.split("/").pop() ?? "";
  if (!/^[A-Za-z0-9]{6}$/.test(code)) return new Response("This Ataste link isn't valid.", { status: 404 });
  return new Response(null, { status: 302, headers: { location: `https://ataste.51-79-240-114.sslip.io/j/${code.toUpperCase()}` } });
});
