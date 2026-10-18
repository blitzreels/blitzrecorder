import { SignOutButton } from "@/components/hosting/sign-out-button";

/** Icon-sized sign out for the sidebar's account row and the phone header. */
export const ShellSignOut = () => <SignOutButton
  className="grid size-8 shrink-0 place-items-center rounded-[8px] text-white/50 transition-colors hover:bg-white/[0.06] hover:text-foreground disabled:opacity-60 [&_svg]:size-4">
  <span className="sr-only">Sign out</span>
</SignOutButton>;
