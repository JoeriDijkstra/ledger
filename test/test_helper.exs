# PDF thumbnailing shells out to pdftoppm (poppler). Tests that rasterize a
# real PDF are tagged `:requires_poppler` and skipped where it isn't
# installed, so a box without poppler runs a green — if smaller — suite.
# Everything around it (enqueueing, preview URLs, cleanup) still runs.
poppler_exclusions =
  if Masthead.Uploads.Thumbnail.available?() do
    []
  else
    IO.puts("pdftoppm not found — skipping tests tagged :requires_poppler")
    [requires_poppler: true]
  end

ExUnit.start(exclude: poppler_exclusions)
Ecto.Adapters.SQL.Sandbox.mode(Masthead.Repo, :manual)
