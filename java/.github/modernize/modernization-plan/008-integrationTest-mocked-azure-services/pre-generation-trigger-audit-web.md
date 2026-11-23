# Pre-Generation Trigger Audit — `web` module `*PostMigrationIT`

| TC ID | Trigger pseudocode | Entry Point Type | Violates forbidden patterns? |
|---|---|---|---|
| TC-WEB-001 | `mockMvc.perform(multipart("/storage/upload").file(sampleJpgPart))` | HTTP | No — HTTP test client against the declared endpoint |
| TC-WEB-002 | `mockMvc.perform(multipart("/storage/upload").file(sampleJpgPart))` | HTTP | No |
| TC-WEB-003 | `mockMvc.perform(multipart("/storage/upload").file(emptyBytesPart("empty.jpg")))` | HTTP | No |
| TC-WEB-004 | `testRestTemplate.postForEntity("/storage/upload", oversizedBinMultipartBody, String.class)` (real over-the-wire HTTP, `webEnvironment = RANDOM_PORT`) | HTTP | No |
| TC-WEB-005 | `mockMvc.perform(multipart("/storage/upload").file(tinyJpgPart, filename="../tiny.jpg"))` | HTTP | No |
| TC-WEB-006 | `mockMvc.perform(multipart("/storage/upload").file(samplePortraitPart, filename="테스트 이미지.png"))` | HTTP | No |
| TC-WEB-007 | `testRestTemplate.postForEntity("/storage/upload", tinyJpgMultipartBody, String.class)` (real over-the-wire HTTP, `webEnvironment = RANDOM_PORT`; `serviceBusTemplate.send(...)` stubbed to throw) | HTTP | No |
| TC-WEB-008 | `mockMvc.perform(get("/storage"))` | HTTP | No |
| TC-WEB-009 | `mockMvc.perform(get("/storage"))` | HTTP | No |
| TC-WEB-010 | `mockMvc.perform(get("/storage"))` | HTTP | No |
| TC-WEB-011 | `mockMvc.perform(get("/storage/view-page/sample.jpg"))` | HTTP | No |
| TC-WEB-012 | `mockMvc.perform(get("/storage/view/sample.jpg"))` | HTTP | No |
| TC-WEB-013 | `mockMvc.perform(get("/storage/view-page/does-not-exist.jpg"))` | HTTP | No |
| TC-WEB-014 | `mockMvc.perform(get("/storage/view/does-not-exist.jpg"))` | HTTP | No |
| TC-WEB-015 | `mockMvc.perform(post("/storage/delete/{key}", seededKey))` | HTTP | No |
| TC-WEB-016 | `mockMvc.perform(post("/storage/delete/sample.jpg"))` | HTTP | No |
| TC-WEB-017 | `mockMvc.perform(post("/storage/delete/does-not-exist.jpg"))` | HTTP | No |
| TC-WEB-018 | `backupMessageProcessor.processBackupMessage(deserializedMessage, mockServiceBusReceivedMessageContext)` (real `@Autowired` Spring-managed bean, `backup`-profile context) | Message-queue listener | **Documented forced adaptation** — see "Note on TC-WEB-018's trigger" in `post-migration-plan-web.md`. All other avenues (real Service Bus namespace, testcontainer/emulator) are unavailable because the infra-decision-table fixes every dependency to `mock` and no broker/emulator is wired in this repository/environment. The call target is the real, container-managed `@Component` bean's public listener method (not a private helper, not a reimplementation of its logic) with its message argument coming straight from the spec's literal JSON trigger body — this is the closest available approximation to "produce a real event on the declared source" under the fixed mock-only constraint, pre-approved by the task owner rather than self-selected to dodge a real dependency that was otherwise reachable. |

All HTTP rows (TC-WEB-001..017) use a real HTTP test client (`MockMvc` for most cases; `TestRestTemplate` over a real embedded server for TC-WEB-004/TC-WEB-007, which need genuine servlet-container multipart-size enforcement and container-level error-page dispatch that MockMvc's mock dispatch cannot provide — see "Note on the dev-profile real-server split" in `post-migration-plan-web.md`) against the exact path/method declared as the Entry Point in `test-cases.md`, with no internal service/SDK call substituted as the trigger. Only TC-WEB-018 deviates from using an HTTP/real-queue trigger, and that deviation is explicitly documented, not silent.
