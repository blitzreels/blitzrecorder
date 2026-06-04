type DataFastFunction = (
  eventName: string,
  properties?: Record<string, string>,
) => void;

declare global {
  interface Window {
    datafast?: DataFastFunction & {
      q?: IArguments[];
    };
  }
}

export {};
