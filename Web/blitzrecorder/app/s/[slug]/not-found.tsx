import Link from "next/link";

export default function UnavailableVideo() {
  return <main className="flex min-h-screen flex-col items-center justify-center gap-4 bg-[#101111] px-8 text-center">
    <h1 className="font-display text-3xl font-semibold">This video is unavailable</h1>
    <p className="max-w-sm text-zinc-400">The owner may have removed it or turned off sharing.</p>
    <Link href="/" className="mt-3 text-sm text-emerald-400">Visit BlitzRecorder</Link>
  </main>;
}
