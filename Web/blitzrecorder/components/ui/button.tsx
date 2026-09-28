import { Button as ButtonPrimitive } from "@base-ui/react/button"
import { cva, type VariantProps } from "class-variance-authority"

import { cn } from "@/lib/utils"

const buttonVariants = cva(
  "group/button inline-flex shrink-0 items-center justify-center gap-2 rounded-control border border-transparent font-medium whitespace-nowrap transition-[background-color,color,opacity] outline-none select-none focus-visible:ring-3 focus-visible:ring-ring/40 active:opacity-75 disabled:pointer-events-none disabled:opacity-40 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
  {
    variants: {
      variant: {
        default: "bg-primary text-primary-foreground hover:bg-primary/90",
        outline: "border-border bg-fill-control text-foreground hover:bg-fill-hover",
        secondary: "border-border bg-fill-control text-foreground hover:bg-fill-hover",
        ghost: "text-faint hover:bg-fill-quiet hover:text-foreground",
        destructive: "bg-fill-control text-record hover:bg-fill-hover",
        link: "text-primary underline-offset-4 hover:underline",
      },
      size: {
        sm: "h-7 px-2 text-xs",
        default: "h-[34px] px-3 text-[13px]",
        lg: "h-10 px-4 text-sm",
        xs: "h-6 px-2 text-[11px]",
        icon: "size-[34px]",
        "icon-xs": "size-6",
        "icon-sm": "size-7",
        "icon-lg": "size-10",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  }
)

function Button({
  className,
  variant = "default",
  size = "default",
  render,
  nativeButton,
  ...props
}: ButtonPrimitive.Props & VariantProps<typeof buttonVariants>) {
  return (
    <ButtonPrimitive
      data-slot="button"
      className={cn(buttonVariants({ variant, size, className }))}
      render={render}
      // A custom `render` element (e.g. an <a>) is not a native <button>.
      // Default `nativeButton` accordingly so Base UI applies the right semantics.
      nativeButton={nativeButton ?? render === undefined}
      {...props}
    />
  )
}

export { Button, buttonVariants }
