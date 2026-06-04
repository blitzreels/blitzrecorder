import { Check } from "@/components/site/icons";

export function CheckItem({ children }: { children: React.ReactNode }) {
  return (
    <li className="flex items-start gap-3">
      <span className="mt-0.5 flex size-5 shrink-0 items-center justify-center rounded-full bg-primary/15 text-primary">
        <Check className="size-3.5" strokeWidth={3} />
      </span>
      <span>{children}</span>
    </li>
  );
}
