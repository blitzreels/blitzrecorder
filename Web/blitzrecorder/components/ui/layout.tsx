import * as React from "react"
import { cva, type VariantProps } from "class-variance-authority"

import { cn } from "@/lib/utils"

const widthVariants = cva("mx-auto", {
  variants: {
    width: {
      sm: "w-[min(820px,calc(100%-32px))]",
      md: "w-[min(900px,calc(100%-32px))]",
      lg: "w-[min(1080px,calc(100%-32px))]",
      xl: "w-[min(1180px,calc(100%-32px))]",
      full: "w-full",
    },
  },
  defaultVariants: {
    width: "xl",
  },
})

function Section({
  className,
  width,
  ...props
}: React.ComponentProps<"section"> & VariantProps<typeof widthVariants>) {
  return (
    <section
      data-slot="section"
      className={cn(widthVariants({ width }), className)}
      {...props}
    />
  )
}

function Container({
  className,
  width,
  ...props
}: React.ComponentProps<"div"> & VariantProps<typeof widthVariants>) {
  return (
    <div
      data-slot="container"
      className={cn(widthVariants({ width }), className)}
      {...props}
    />
  )
}

function Article({ className, ...props }: React.ComponentProps<"article">) {
  return <article data-slot="article" className={className} {...props} />
}

export { Section, Container, Article, widthVariants }
