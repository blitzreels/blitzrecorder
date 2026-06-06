import * as React from "react"
import { cva, type VariantProps } from "class-variance-authority"

import { cn } from "@/lib/utils"

type HeadingLevel = 1 | 2 | 3 | 4

const headingLevels: Record<HeadingLevel, string> = {
  1: "text-5xl leading-[0.95] font-black sm:text-6xl",
  2: "text-4xl leading-[1.02] font-black sm:text-6xl",
  3: "text-xl leading-tight font-bold",
  4: "text-lg leading-tight font-bold",
}

function Heading({
  className,
  level = 2,
  as,
  ...props
}: React.ComponentProps<"h2"> & {
  level?: HeadingLevel
  /** Override the rendered element without changing the visual level. */
  as?: "h1" | "h2" | "h3" | "h4"
}) {
  const Tag = as ?? (`h${level}` as "h1" | "h2" | "h3" | "h4")
  return (
    <Tag
      data-slot="heading"
      className={cn(
        "font-display tracking-tight text-balance",
        headingLevels[level],
        className
      )}
      {...props}
    />
  )
}

const paragraphVariants = cva("", {
  variants: {
    tone: {
      default: "",
      muted: "text-muted-foreground",
      faint: "text-faint",
    },
    size: {
      sm: "text-sm leading-6",
      base: "text-base leading-7",
      lg: "text-lg leading-8",
    },
  },
  defaultVariants: {
    tone: "muted",
    size: "lg",
  },
})

function Paragraph({
  className,
  tone,
  size,
  ...props
}: React.ComponentProps<"p"> & VariantProps<typeof paragraphVariants>) {
  return (
    <p
      data-slot="paragraph"
      className={cn(paragraphVariants({ tone, size }), className)}
      {...props}
    />
  )
}

export { Heading, Paragraph, headingLevels, paragraphVariants }
