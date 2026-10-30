# Browser check

A browser check edits no file.

1. Find the dev-server script of the repository, such as the `start` or `dev` script in
   `package.json`. Never invent a command.
2. If a host application consumes the repository, or the repository has no dev-server script,
   report `SKIPPED: no dev server` and stop.
3. Start the dev server with `Start-Process -PassThru`. Record the process ID (PID) and the
   `StartTime` of the process.
4. Pass `--host 127.0.0.1` to the script when the script accepts it. Report the address that the
   server binds to.
5. Wait at most 60 seconds for the server to answer. On timeout, stop the server by the stop steps
   below. Then report `FAILED: dev server did not answer in 60 s` and stop.
6. Open the page with `browser_navigate`.
7. Check each user-visible acceptance criterion that the prompt lists. Use `browser_snapshot` to
   read the page.
8. Read the console messages with `browser_console_messages`. Report each error.
9. Record the current time with `Get-Date`. Do this before the first screenshot.
10. Call `browser_take_screenshot` with no `filename`. Playwright saves the file in
    `$env:TEMP\playwright-mcp`.
11. Copy only the files that the result of `browser_take_screenshot` names. Copy them to the
    scratchpad path that the prompt names.
12. If the result names no file, copy only the files in `$env:TEMP\playwright-mcp` with a
    `LastWriteTime` after the time that you recorded.
13. Copy no other file from `$env:TEMP\playwright-mcp`. Delete no file in that folder.
14. Run the stop steps below.

## The stop steps

1. Run `Get-Process -Id <pid>`. Check that its `StartTime` equals the `StartTime` that you recorded.
2. If the `StartTime` is the same, run `taskkill /PID <pid> /T` to stop the process tree.
3. If the `StartTime` differs, stop no process. Report the difference.
4. Close the browser with `browser_close`.

Never stop a process that you did not start.

If the app needs a login, run the stop steps first. Then report `SKIPPED: login needed` and stop.
Do not enter a credential.

Report each criterion as pass or fail, with the evidence. Name each screenshot path.
