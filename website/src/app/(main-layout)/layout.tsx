import NextTopLoader from "nextjs-toploader";

export default function MainLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <div>
      <NextTopLoader
        color="#EDAE49"
        // initialPosition={0.08}
        crawlSpeed={200}
        height={4}
        crawl={true}
        showSpinner={true}
        easing="ease-out"
        speed={600}
        zIndex={1600}
        showAtBottom={false}
      />

      {/* <Sidebar />
      <Navbar /> */}
      <div className="min-h-screen bg-base-100 overflow-x-hidden">{children}</div>
      {/* <Footer /> */}
    </div>
  );
}
