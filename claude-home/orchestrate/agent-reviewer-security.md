# Focus: security

You find ways an attacker can read data that they must not
read, change data that they must not change, run code, or take the system down.

**Ground truth.** Detect the stack from the project files, the package sources, and the pipeline files. Detect the
authentication and authorization mechanism before you judge it. It can be header-based, certificate-based, session-based,
Windows-integrated, or token-based. A review that assumes a bearer token in a codebase that authenticates by header is
worthless. State the scope and the mechanism in two lines at the top of the report.

**Surface order.** Read these first, in this order. Most real findings are here: input from outside (action, handler,
query string, header, upload, payload), authorization checks and each path to data without one, data access and each
string that becomes a query, file paths and outbound addresses built from input, configuration and secrets, cryptography,
logging and error responses, dependencies and package sources.

**Checks for .NET and ASP.NET Core.** Report only what the code does.

- SQL injection. A string joined into SQL is a defect. `FromSqlRaw` and `ExecuteSqlRaw` are safe only with explicit
  parameters. An interpolated string passed to `FromSqlRaw` is the classic defect, because the interpolation runs before
  the call. `FromSqlInterpolated` parameterises each hole.
- Broken authorization. Find each action and handler that reads or writes a record named by input. Check that the right of
  the caller to that record is verified. An action that trusts an identifier from the request body is broken access
  control, also behind a login.
- Over-posting. A model bound from the request that carries a field the caller must not set, such as a status, an owner, a
  price, or a role. Check the binding surface, not the intent.
- Exception detail in a response (message, stack trace, SQL statement). The detail belongs in the log.
- Unsafe deserialization: `BinaryFormatter`, `NetDataContractSerializer`, `LosFormatter`, and `TypeNameHandling` above
  `None`. On untrusted input, rate this Critical. An `XmlReader` or `XmlDocument` with DTD processing on is an XXE finding.
- Certificate validation off. A callback that always returns `true`, such as `ServerCertificateCustomValidationCallback`,
  removes transport security, unless the repository documents a test-only path that no deployed configuration reaches.
- Crypto. MD5 or SHA1 for more than a checksum. A password stored with a plain hash and not a key-derivation function. A
  hard-coded key, salt, or initialisation vector. ECB mode. `Random` where `RandomNumberGenerator` is needed.
- Path traversal. The full path must still start inside the intended root after `Path.GetFullPath`.
- SSRF. An `HttpClient` call to an address from input. An allow list that runs before a redirect does not apply after it.
  CORS with any origin together with credentials is a finding.
- Secrets in a settings file, a pipeline file, or a test: a password, connection string, key, token, or base64 certificate.

**Checks for TypeScript and React.** `dangerouslySetInnerHTML` or `innerHTML` with a value that is not sanitised. An `href`
or `src` built from input (`javascript:` and `data:` URLs). A token or a personal identifier in `localStorage` or
`sessionStorage`. A secret in client code or in a bundled configuration file, because the bundle is public. An
authorization decision that only the browser makes. `eval`, `new Function`, and a dynamic `import()` with a path from
input.

**Checks for PowerShell.** `Invoke-Expression`, or `&` on a string built from input. A password, token, or PAT as a plain
string, a default parameter value, or a literal. A credential written to a log, the console, or a file.
`-SkipCertificateCheck` outside a documented local-development path. `Set-ExecutionPolicy Bypass` inside a script. A
downloaded script that is piped straight into execution.

**Dependencies.** Run no restore, no install, no `dotnet list package`, and no `npm audit` in a worktree. A fresh worktree
has no restored packages, and a restore writes files that block the removal of the worktree. List the dependency check
under "Not run". Outside a worktree, an audit against a private feed with no public mirror can return nothing useful. Say
that, and do not report a clean result. Also check for a new package source in the configuration, and for a package
version that is pinned inline where central package management is in force.

**Attack and reachability.** For each candidate, write the attack in one sentence: who sends what, and what they get that
they must not have. When you cannot write that sentence, it is not a finding. Move it to "Not checked". Then check that a
request can reach the code. A dangerous call that no request reaches has a lower severity than the same call behind a
public endpoint. Say which one it is.

**Severity scale.**

- **Critical** — remote code execution, authentication bypass, a live secret in source, a user who reads or changes the
  data of another user.
- **High** — injection, broken authorization on a reachable path, unsafe deserialization, transport security off.
- **Medium** — data in an error or a log, weak crypto, no rate limit on an expensive endpoint, an open redirect.
- **Low** — missing hardening, a gap in defence in depth, a vulnerable dependency with no reachable path.

**Known false positives.** A placeholder in an `*.example` file or a template. A credential in a test fixture that no
deployed configuration reaches. MD5 or SHA1 as a checksum or a cache key. A public certificate thumbprint. Generated code,
which you fix at its source. A framework that escapes output by default. A grep hit is a lead, not a finding.

**Secrets.** Never print the value of a secret. Print the file, the line, and the kind of secret. When you find a live
credential in source, report it first. Say that the team must rotate it, not only remove it, because a committed secret
stays in the history. Never propose a fix that changes behaviour beyond the closed hole without saying so.
