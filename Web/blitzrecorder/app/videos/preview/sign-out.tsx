import Link from "next/link";
import { LogOut } from "lucide-react";
import { signInPath } from "@/lib/hosting/paths";

/** The fixture has no session, so sign out just shows the sign-in page. */
export const PreviewSignOut = () => <Link href={signInPath} aria-label="Sign out"
  className="grid size-8 shrink-0 place-items-center rounded-[8px] text-white/50 transition-colors hover:bg-white/[0.06] hover:text-foreground">
  <LogOut className="size-4" />
</Link>;
