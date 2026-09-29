import Link from "next/link";

export const metadata = { title: "Video hosting — BlitzRecorder", robots: { index: false, follow: false } };

export default async function HostingComplete({ searchParams }: { searchParams: Promise<{ cancelled?: string }> }) {
  const cancelled = (await searchParams).cancelled === "1";
  return <main className="mx-auto flex min-h-screen max-w-xl flex-col justify-center gap-6 px-6 py-20">
    <p className="text-sm text-neutral-400">BlitzRecorder · Video hosting</p>
    <h1 className="text-3xl font-semibold tracking-tight">{cancelled ? "Continue when you’re ready" : "Return to BlitzRecorder"}</h1>
    <p className="text-neutral-400">{cancelled ? "Your video remains on your Mac. No upload has started."
      : "Return to the Share panel in BlitzRecorder. Your subscription updates automatically once payment is confirmed."}</p>
    <p className="text-sm text-neutral-500">Your local exports stay available with or without a hosting subscription.</p>
    <Link href="/" className="text-sm underline underline-offset-4">Back to BlitzRecorder</Link>
  </main>;
}
