/** Shown inside the shell while a dashboard page loads, so the sidebar never blinks. */
export default function DashboardLoading() {
  return <div aria-busy="true" aria-label="Loading" className="animate-pulse">
    <div className="h-9 w-48 rounded-[10px] bg-white/[0.06]" />
    <div className="mt-3 h-4 w-80 max-w-full rounded-full bg-white/[0.04]" />
    <div className="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {Array.from({ length: 3 }, (_, index) => <div key={index} className="aspect-video rounded-[16px] bg-white/[0.04]" />)}
    </div>
  </div>;
}
