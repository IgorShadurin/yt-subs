(async () => {
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline) {
    const result = globalThis.YTSubsReader.read(document, location.href);
    if (result) return result;
    await new Promise(resolve => setTimeout(resolve, 400));
  }
  throw new Error('Exact counter not found. Open Studio and check the channel and sign-in.');
})();
