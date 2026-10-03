"use client";

import { useRouter } from "next/navigation";
import { useEffect, useRef, useState, type FormEvent } from "react";
import { CircleAlert, LoaderCircle, Mail } from "lucide-react";
import { Button } from "@/components/ui/button";

type Step = { kind: "email" } | { kind: "code"; email: string; challenge: string } | { kind: "done" };

const CODE_LENGTH = 6;
/** Pasted text may be a whole email line ("Your code is 482915") or a grouped code ("482 915"). */
const codeFrom = (text: string) => (text.match(/\d{6}/)?.[0] ?? text.replace(/\D/g, "")).slice(0, CODE_LENGTH);
const UNREACHABLE = "Can’t reach BlitzRecorder. Check your connection and try again.";
const SERVER_FAILED = "Something went wrong on our side. Try again in a moment.";

class RequestError extends Error {
  constructor(message: string, readonly status: number) { super(message); }
}

async function post<T>({ url, body }: { url: string; body: unknown }): Promise<T> {
  let response: Response;
  try {
    response = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  } catch {
    throw new RequestError(UNREACHABLE, 0);
  }
  const data = await response.json().catch(() => null) as (T & { error?: string }) | null;
  if (!response.ok || !data) throw new RequestError(data?.error ?? SERVER_FAILED, response.status);
  return data;
}

const useCountdown = () => {
  const [left, setLeft] = useState(0);
  useEffect(() => {
    if (left <= 0) return;
    const timer = window.setTimeout(() => setLeft((value) => value - 1), 1000);
    return () => window.clearTimeout(timer);
  }, [left]);
  return { left, start: setLeft };
};

const field = "h-11 w-full rounded-control border border-border bg-fill-quiet px-3 text-[15px] outline-none transition-colors placeholder:text-faint focus:border-foreground/30 disabled:opacity-60";

const ErrorText = ({ children }: { children: string }) => <p role="alert" className="flex items-start gap-2 text-sm text-pretty text-destructive">
  <CircleAlert className="mt-0.5 size-4 shrink-0" /> {children}
</p>;

const CodeInput = ({ value, onChange, disabled, invalid }: {
  value: string; onChange: (value: string) => void; disabled: boolean; invalid: boolean;
}) => {
  const [focused, setFocused] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  useEffect(() => { if (!disabled) inputRef.current?.focus(); }, [disabled]);
  return <div className="relative">
    <div aria-hidden className="grid grid-cols-6 gap-2">
      {Array.from({ length: CODE_LENGTH }, (_, index) => {
        const active = focused && !disabled && index === Math.min(value.length, CODE_LENGTH - 1);
        return <div key={index} className={`flex h-12 items-center justify-center rounded-control border bg-fill-quiet font-mono text-xl transition-colors ${
          invalid ? "border-destructive/60" : active ? "border-foreground/40 bg-fill-control" : "border-border"}`}>
          {value[index] ?? (active ? <span className="h-5 w-px animate-pulse bg-foreground" /> : null)}
        </div>;
      })}
    </div>
    <input ref={inputRef} value={value} disabled={disabled} inputMode="numeric" autoComplete="one-time-code"
      aria-label="6-digit sign-in code" aria-invalid={invalid || undefined}
      onFocus={() => setFocused(true)} onBlur={() => setFocused(false)}
      onPaste={(event) => { event.preventDefault(); onChange(codeFrom(event.clipboardData.getData("text"))); }}
      onChange={(event) => onChange(codeFrom(event.target.value))}
      className="absolute inset-0 size-full cursor-text opacity-0" />
  </div>;
};

export const SignInForm = ({ next, intro }: { next: string; intro: string }) => {
  const router = useRouter();
  const [step, setStep] = useState<Step>({ kind: "email" });
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [resent, setResent] = useState(false);
  const cooldown = useCountdown();
  const emailRef = useRef<HTMLInputElement>(null);

  const sendCode = async (address: string) => {
    setPending(true);
    setError(null);
    try {
      const result = await post<{ challenge: string; email: string; retryAfter: number }>({
        url: "/api/hosting/sign-in/request", body: { email: address },
      });
      setStep({ kind: "code", email: result.email, challenge: result.challenge });
      setCode("");
      cooldown.start(result.retryAfter);
      return true;
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : SERVER_FAILED);
      return false;
    } finally {
      setPending(false);
    }
  };

  const verify = async (value: string) => {
    if (step.kind !== "code" || pending) return;
    setPending(true);
    setError(null);
    try {
      await post({ url: "/api/hosting/session", body: { challenge: step.challenge, code: value } });
      setStep({ kind: "done" });
      router.replace(next);
      router.refresh();
    } catch (reason) {
      const status = reason instanceof RequestError ? reason.status : 0;
      setError(status === 400
        ? "That code is wrong or has expired. Check the latest email, or send a new code."
        : reason instanceof Error ? reason.message : SERVER_FAILED);
      setCode("");
    } finally {
      setPending(false);
    }
  };

  const submitEmail = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    void sendCode(email.trim());
  };

  const changeCode = (value: string) => {
    setCode(value);
    if (error) setError(null);
    if (value.length === CODE_LENGTH) void verify(value);
  };

  const resend = async () => {
    if (step.kind !== "code") return;
    setResent(await sendCode(step.email));
  };

  const changeEmail = () => {
    setStep({ kind: "email" });
    setError(null);
    setResent(false);
    window.setTimeout(() => emailRef.current?.select(), 0);
  };

  if (step.kind === "done") {
    return <div role="status" className="flex flex-col items-center gap-3 text-center">
      <LoaderCircle className="size-6 animate-spin text-muted-foreground" />
      <p className="text-sm text-muted-foreground">Signed in. Opening your videos…</p>
    </div>;
  }

  if (step.kind === "email") {
    return <form onSubmit={submitEmail} className="flex flex-col gap-6">
      <div className="flex flex-col gap-2">
        <h1 className="font-display text-2xl font-semibold tracking-tight">Sign in to your videos</h1>
        <p className="text-sm text-muted-foreground">{intro}</p>
      </div>
      <div className="flex flex-col gap-3">
        <label className="flex flex-col gap-1.5">
          <span className="text-xs font-medium text-muted-foreground">Email</span>
          <input ref={emailRef} type="email" required autoFocus autoComplete="email" inputMode="email" value={email}
            placeholder="you@example.com" disabled={pending} aria-invalid={Boolean(error) || undefined}
            onChange={(event) => { setEmail(event.target.value); if (error) setError(null); }} className={field} />
        </label>
        {error && <ErrorText>{error}</ErrorText>}
        <Button type="submit" size="lg" disabled={pending || !email.trim()}>
          {pending ? <><LoaderCircle className="animate-spin" /> Sending code…</> : "Continue with email"}
        </Button>
      </div>
      <p className="text-xs text-pretty text-faint">Use the email you signed in with in the BlitzRecorder app. No password needed.</p>
    </form>;
  }

  return <div className="flex flex-col gap-6">
    <div className="flex flex-col gap-2">
      <span className="mb-1 flex size-10 items-center justify-center rounded-tile bg-fill-control text-muted-foreground">
        <Mail className="size-5" />
      </span>
      <h1 className="font-display text-2xl font-semibold tracking-tight">Check your email</h1>
      <p className="text-sm text-muted-foreground">
        Enter the 6-digit code sent to <span className="text-foreground">{step.email}</span>.{" "}
        <button type="button" onClick={changeEmail} className="text-foreground underline underline-offset-4 hover:text-primary">
          Change
        </button>
      </p>
    </div>
    <form className="flex flex-col gap-3" onSubmit={(event) => { event.preventDefault(); void verify(code); }}>
      <CodeInput value={code} onChange={changeCode} disabled={pending} invalid={Boolean(error)} />
      {error && <ErrorText>{error}</ErrorText>}
      {resent && !error && <p role="status" className="text-sm text-muted-foreground">New code sent. Use the most recent email.</p>}
      <Button type="submit" size="lg" disabled={pending || code.length < CODE_LENGTH}>
        {pending ? <><LoaderCircle className="animate-spin" /> Checking…</> : "Sign in"}
      </Button>
    </form>
    <div className="flex items-center justify-between gap-4 text-xs text-pretty text-faint">
      <span>Can’t find it? Check spam. Codes expire after 10 minutes.</span>
      <button type="button" onClick={resend} disabled={pending || cooldown.left > 0}
        className="shrink-0 font-medium text-muted-foreground transition-colors hover:text-foreground disabled:pointer-events-none disabled:text-faint">
        {cooldown.left > 0 ? `Resend in ${cooldown.left}s` : "Resend code"}
      </button>
    </div>
  </div>;
};
