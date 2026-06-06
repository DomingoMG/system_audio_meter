document$.subscribe(() => {
  if (typeof mermaid !== "undefined") {
    mermaid.initialize({ startOnLoad: true });
  }
});
