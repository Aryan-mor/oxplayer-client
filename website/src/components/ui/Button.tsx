import React, { ButtonHTMLAttributes, ReactNode } from "react";
import clsx from "clsx";

/* ---------------- Types ---------------- */

type ButtonAction = "primary" | "secondary";
type ButtonVariant = "solid" | "outline";
type ButtonSize = "sm" | "md" | "lg";

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  children: ReactNode;
  action?: ButtonAction;
  variant?: ButtonVariant;
  size?: ButtonSize;
  loading?: boolean;
  style?: React.CSSProperties;
  className?: string;
}

/* ---------------- Component ---------------- */

export default function Button({
  children,
  action = "primary",
  variant = "solid",
  size = "md",
  loading = false,
  disabled = false,
  style,
  className,
  ...props
}: ButtonProps) {
  /* Base Styles */

  const baseClass = clsx(
    "inline-flex items-center justify-center gap-2 cursor-pointer",
    "font-bold text-center no-underline",
    "rounded-xl",
    "transition-all duration-300 ease-in-out",
    "select-none",

    "hover:-translate-y-1",
    "active:translate-y-1 active:shadow-none",

    disabled && "opacity-50 cursor-not-allowed",
    loading && "opacity-70 cursor-wait",
  );

  /* Action + Variant Styles */

  const actionClasses: Record<ButtonAction, Record<ButtonVariant, string>> = {
    primary: {
      solid: clsx("text-white", "bg-gradient-to-r from-primary via-secondary-500 to-secondary", "hover:scale-105 hover:shadow-lg"),

      outline: clsx(
        "relative z-0 text-white",
        "before:content-[''] before:absolute before:inset-0 before:-z-10",
        "before:p-[2px] before:rounded-xl",
        "before:bg-gradient-to-r before:from-primary before:via-secondary-500 before:to-secondary",
        "after:content-[''] after:absolute after:inset-[2px] after:-z-10",
        "after:bg-base-100 after:rounded-xl",
        "hover:scale-105 hover:shadow-lg",
      ),
    },

    secondary: {
      solid: clsx("text-white", "bg-gradient-to-r from-primary via-secondary-500 to-secondary", "hover:scale-105 hover:shadow-lg"),

      outline: clsx(
        "relative z-0 text-white",
        "before:content-[''] before:absolute before:inset-0 before:-z-10",
        "before:p-[2px] before:rounded-xl",
        "before:bg-gradient-to-r before:from-pink-500 before:via-purple-500 before:to-indigo-500",
        "after:content-[''] after:absolute after:inset-[2px] after:-z-10",
        "after:bg-base-100 after:rounded-xl",
        "hover:scale-105 hover:shadow-lg",
      ),
    },
  };

  /* Sizes */

  const sizeClasses: Record<ButtonSize, string> = {
    sm: "px-3 py-2 text-sm",

    md: "px-4 py-2 text-sm sm:px-5 sm:py-3 sm:text-base",

    lg: "px-5 py-3 text-base sm:px-6 sm:py-4 sm:text-lg md:px-7 md:py-5 md:text-xl",
  };

  return (
    <button
      disabled={disabled || loading}
      style={style}
      className={clsx(baseClass, actionClasses[action][variant], sizeClasses[size], className)}
      {...props}
    >
      {loading ? (
        <>
          <span className="loading loading-spinner loading-sm" />
          Please wait...
        </>
      ) : (
        children
      )}
    </button>
  );
}
