// FIXTURE FILE — webhook route (synthetic)
export async function POST(req: Request) {
  const sig = req.headers.get("x-signature") ?? "";
  const body = await req.text();
  if (!verifyHmacSignature(body, sig)) {
    return new Response("invalid signature", { status: 401 });
  }
  return new Response("ok", { status: 200 });
}
function verifyHmacSignature(body: string, sig: string): boolean {
  // NOTE: plain string comparison — NOT constant-time
  return computeHmac(body) === sig;
}
function computeHmac(body: string): string {
  return "stub-" + body.length;
}
