# Security Assessment Report

**Generated:** 2026-11-23T02:19:07.6219267Z

## Summary

| Metric | Count |
|--------|-------|
| Total Findings | 92 |
| CVE Vulnerabilities | 79 |
| CWE Vulnerabilities | 13 |
| Total Rules Assessed | 59 |
| Rules Passed | 46 |

### By Severity

| Severity | Count |
|----------|-------|
| mandatory | 80 |
| optional | 6 |
| potential | 6 |

## CVE Findings (Dependency Vulnerabilities)

### CVE-2023-6378: logback serialization vulnerability

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:21

[CVE-2023-6378](https://github.com/advisories/GHSA-vmq6-5m68-f53m): logback serialization vulnerability

Severity: HIGH

Affected dependencies:
  - ch.qos.logback:logback-classic:1.2.12 (transitive, pulled by org.springframework.boot:spring-boot-starter-thymeleaf:2.7.18 at web/pom.xml:21)
  - ch.qos.logback:logback-core:1.2.12 (transitive, pulled by org.springframework.boot:spring-boot-starter-thymeleaf:2.7.18 at web/pom.xml:21)

Recommended fix:
  - Upgrade ch.qos.logback:logback-classic to 1.4.12 or later
  - Upgrade ch.qos.logback:logback-core to 1.4.12 or later
  - Upgrade ch.qos.logback:logback-classic to 1.3.12 or later
  - Upgrade ch.qos.logback:logback-core to 1.3.12 or later
  - Upgrade ch.qos.logback:logback-core to 1.2.13 or later
  - Upgrade ch.qos.logback:logback-classic to 1.2.13 or later

### CVE-2023-6481: Logback is vulnerable to an attacker mounting a Denial-Of-Service attack by sending poisoned data

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:21

[CVE-2023-6481](https://github.com/advisories/GHSA-gm62-rw4g-vrc4): Logback is vulnerable to an attacker mounting a Denial-Of-Service attack by sending poisoned data

Severity: HIGH

Affected dependencies:
  - ch.qos.logback:logback-core:1.2.12 (transitive, pulled by org.springframework.boot:spring-boot-starter-thymeleaf:2.7.18 at web/pom.xml:21)

Recommended fix:
  - Upgrade ch.qos.logback:logback-core to 1.4.14 or later
  - Upgrade ch.qos.logback:logback-core to 1.3.14 or later
  - Upgrade ch.qos.logback:logback-core to 1.2.13 or later

### CVE-2022-25857: Uncontrolled Resource Consumption in snakeyaml

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:21

[CVE-2022-25857](https://github.com/advisories/GHSA-3mc7-4q67-w48m): Uncontrolled Resource Consumption in snakeyaml

Severity: HIGH

Affected dependencies:
  - org.yaml:snakeyaml:1.30 (transitive, pulled by org.springframework.boot:spring-boot-starter-thymeleaf:2.7.18 at web/pom.xml:21)

Recommended fix:
  - Upgrade org.yaml:snakeyaml to 1.31 or later

### CVE-2022-1471: SnakeYaml Constructor Deserialization Remote Code Execution

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:21

[CVE-2022-1471](https://github.com/advisories/GHSA-mjmj-j48q-9wg2): SnakeYaml Constructor Deserialization Remote Code Execution

Severity: HIGH

Affected dependencies:
  - org.yaml:snakeyaml:1.30 (transitive, pulled by org.springframework.boot:spring-boot-starter-thymeleaf:2.7.18 at web/pom.xml:21)

Recommended fix:
  - Upgrade org.yaml:snakeyaml to 2.0 or later

### CVE-2026-40477: Improper restriction of the scope of accessible objects in Thymeleaf expressions

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:21

[CVE-2026-40477](https://github.com/advisories/GHSA-r4v4-5mwr-2fwr): Improper restriction of the scope of accessible objects in Thymeleaf expressions

Severity: CRITICAL

Affected dependencies:
  - org.thymeleaf:thymeleaf-spring5:3.0.15.RELEASE (transitive, pulled by org.springframework.boot:spring-boot-starter-thymeleaf:2.7.18 at web/pom.xml:21)
  - org.thymeleaf:thymeleaf:3.0.15.RELEASE (transitive, pulled by org.springframework.boot:spring-boot-starter-thymeleaf:2.7.18 at web/pom.xml:21)

Recommended fix:
  - Upgrade org.thymeleaf:thymeleaf to 3.1.4.RELEASE or later
  - Upgrade org.thymeleaf:thymeleaf-spring5 to 3.1.4.RELEASE or later
  - Upgrade org.thymeleaf:thymeleaf-spring6 to 3.1.4.RELEASE or later

### CVE-2026-40478: Improper neutralization of specific syntax patterns for unauthorized expressions in Thymeleaf

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:21

[CVE-2026-40478](https://github.com/advisories/GHSA-xjw8-8c5c-9r79): Improper neutralization of specific syntax patterns for unauthorized expressions in Thymeleaf

Severity: CRITICAL

Affected dependencies:
  - org.thymeleaf:thymeleaf-spring5:3.0.15.RELEASE (transitive, pulled by org.springframework.boot:spring-boot-starter-thymeleaf:2.7.18 at web/pom.xml:21)
  - org.thymeleaf:thymeleaf:3.0.15.RELEASE (transitive, pulled by org.springframework.boot:spring-boot-starter-thymeleaf:2.7.18 at web/pom.xml:21)

Recommended fix:
  - Upgrade org.thymeleaf:thymeleaf to 3.1.4.RELEASE or later
  - Upgrade org.thymeleaf:thymeleaf-spring5 to 3.1.4.RELEASE or later
  - Upgrade org.thymeleaf:thymeleaf-spring6 to 3.1.4.RELEASE or later

### CVE-2026-41901: Sandboxed Thymeleaf expressions vulnerable to improper recognition of unauthorized syntax patterns

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:21

[CVE-2026-41901](https://github.com/advisories/GHSA-c9ph-gxww-7744): Sandboxed Thymeleaf expressions vulnerable to improper recognition of unauthorized syntax patterns

Severity: CRITICAL

Affected dependencies:
  - org.thymeleaf:thymeleaf-spring5:3.0.15.RELEASE (transitive, pulled by org.springframework.boot:spring-boot-starter-thymeleaf:2.7.18 at web/pom.xml:21)
  - org.thymeleaf:thymeleaf:3.0.15.RELEASE (transitive, pulled by org.springframework.boot:spring-boot-starter-thymeleaf:2.7.18 at web/pom.xml:21)

Recommended fix:
  - Upgrade org.thymeleaf:thymeleaf to 3.1.5.RELEASE or later
  - Upgrade org.thymeleaf:thymeleaf-spring5 to 3.1.5.RELEASE or later
  - Upgrade org.thymeleaf:thymeleaf-spring6 to 3.1.5.RELEASE or later

### CVE-2026-54512: jackson-databind has a PolymorphicTypeValidator bypass via generic type parameters that allows arbitrary class instantiation

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** worker/pom.xml:43

[CVE-2026-54512](https://github.com/advisories/GHSA-j3rv-43j4-c7qm): jackson-databind has a PolymorphicTypeValidator bypass via generic type parameters that allows arbitrary class instantiation

Severity: HIGH

Affected dependencies:
  - com.fasterxml.jackson.core:jackson-databind:2.13.5 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at worker/pom.xml:43)

Recommended fix:
  - Upgrade com.fasterxml.jackson.core:jackson-databind to 2.18.8 or later
  - Upgrade com.fasterxml.jackson.core:jackson-databind to 3.1.4 or later
  - Upgrade com.fasterxml.jackson.core:jackson-databind to 2.21.4 or later
  - Upgrade tools.jackson.core:jackson-databind to 3.1.4 or later

### CVE-2026-54513: jackson-databind has an array subtype allowlist bypass in BasicPolymorphicTypeValidator (allowIfSubTypeIsArray)

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** worker/pom.xml:43

[CVE-2026-54513](https://github.com/advisories/GHSA-rmj7-2vxq-3g9f): jackson-databind has an array subtype allowlist bypass in BasicPolymorphicTypeValidator (allowIfSubTypeIsArray)

Severity: HIGH

Affected dependencies:
  - com.fasterxml.jackson.core:jackson-databind:2.13.5 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at worker/pom.xml:43)

Recommended fix:
  - Upgrade com.fasterxml.jackson.core:jackson-databind to 2.18.8 or later
  - Upgrade com.fasterxml.jackson.core:jackson-databind to 2.21.4 or later
  - Upgrade com.fasterxml.jackson.core:jackson-databind to 3.1.4 or later
  - Upgrade tools.jackson.core:jackson-databind to 3.1.4 or later

### CVE-2026-91776: jackson-databind retains every unknown raw type ID 

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** worker/pom.xml:43

[CVE-2026-91776](https://github.com/advisories/GHSA-wv8q-qhhj-9h54): jackson-databind retains every unknown raw type ID 

Severity: HIGH

Affected dependencies:
  - com.fasterxml.jackson.core:jackson-databind:2.13.5 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at worker/pom.xml:43)

Recommended fix:
  - Upgrade com.fasterxml.jackson.core:jackson-databind to 2.18.11 or later
  - Upgrade com.fasterxml.jackson.core:jackson-databind to 2.21.7 or later
  - Upgrade com.fasterxml.jackson.core:jackson-databind to 2.22.3 or later
  - Upgrade tools.jackson.core:jackson-databind to 3.1.7 or later
  - Upgrade tools.jackson.core:jackson-databind to 3.2.3 or later

### CVE-2026-91777: jackson-databind quadratic forward-reference completion 

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** worker/pom.xml:43

[CVE-2026-91777](https://github.com/advisories/GHSA-cxp5-3px4-pw24): jackson-databind quadratic forward-reference completion 

Severity: HIGH

Affected dependencies:
  - com.fasterxml.jackson.core:jackson-databind:2.13.5 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at worker/pom.xml:43)

Recommended fix:
  - Upgrade com.fasterxml.jackson.core:jackson-databind to 2.21.7 or later
  - Upgrade tools.jackson.core:jackson-databind to 3.1.7 or later
  - Upgrade tools.jackson.core:jackson-databind to 3.2.3 or later
  - Upgrade com.fasterxml.jackson.core:jackson-databind to 2.18.11 or later
  - Upgrade com.fasterxml.jackson.core:jackson-databind to 2.22.3 or later

### CVE-2025-52999: jackson-core can throw a StackoverflowError when processing deeply nested data

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2025-52999](https://github.com/advisories/GHSA-h46c-h94j-95f3): jackson-core can throw a StackoverflowError when processing deeply nested data

Severity: HIGH

Affected dependencies:
  - com.fasterxml.jackson.core:jackson-core:2.13.5 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade com.fasterxml.jackson.core:jackson-core to 2.15.0 or later

### CVE-2026-68494: jackson-core: Async parser maxNumberLength bypass via chunked digit accumulation (incomplete fix for GHSA-72hv-8253-57qq)

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2026-68494](https://github.com/advisories/GHSA-r7wm-3cxj-wff9): jackson-core: Async parser maxNumberLength bypass via chunked digit accumulation (incomplete fix for GHSA-72hv-8253-57qq)

Severity: HIGH

Affected dependencies:
  - com.fasterxml.jackson.core:jackson-core:2.13.5 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade com.fasterxml.jackson.core:jackson-core to 2.18.8 or later
  - Upgrade com.fasterxml.jackson.core:jackson-core to 2.21.4 or later
  - Upgrade tools.jackson.core:jackson-core to 3.1.4 or later

### CVE-2026-89425: jackson-core: UTF8DataInputJsonParser._reportInvalidToken() missing maxErrorTokenLength limit -> unbounded StringBuilder growth (DoS)

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2026-89425](https://github.com/advisories/GHSA-7hhh-6rmp-j9qf): jackson-core: UTF8DataInputJsonParser._reportInvalidToken() missing maxErrorTokenLength limit -> unbounded StringBuilder growth (DoS)

Severity: HIGH

Affected dependencies:
  - com.fasterxml.jackson.core:jackson-core:2.13.5 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade com.fasterxml.jackson.core:jackson-core to 2.21.7 or later
  - Upgrade com.fasterxml.jackson.core:jackson-core to 2.22.3 or later
  - Upgrade tools.jackson.core:jackson-core to 3.1.7 or later
  - Upgrade tools.jackson.core:jackson-core to 3.2.3 or later
  - Upgrade com.fasterxml.jackson.core:jackson-core to 2.18.11 or later

### CVE-2024-34750: Apache Tomcat - Denial of Service

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2024-34750](https://github.com/advisories/GHSA-wm9w-rjj3-j356): Apache Tomcat - Denial of Service

Severity: HIGH

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.0-M21 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.25 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.90 or later
  - Upgrade org.apache.tomcat:tomcat-coyote to 11.0.0-M21 or later
  - Upgrade org.apache.tomcat:tomcat-coyote to 10.1.25 or later
  - Upgrade org.apache.tomcat:tomcat-coyote to 9.0.90 or later

### CVE-2024-38286: Apache Tomcat Allocation of Resources Without Limits or Throttling vulnerability

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2024-38286](https://github.com/advisories/GHSA-7jqf-v358-p8g7): Apache Tomcat Allocation of Resources Without Limits or Throttling vulnerability

Severity: HIGH

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat:tomcat-coyote to 11.0.0-M21 or later
  - Upgrade org.apache.tomcat:tomcat-coyote to 10.1.25 or later
  - Upgrade org.apache.tomcat:tomcat-coyote to 9.0.90 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.0-M21 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.25 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.90 or later

### CVE-2024-50379: Apache Tomcat Time-of-check Time-of-use (TOCTOU) Race Condition vulnerability

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2024-50379](https://github.com/advisories/GHSA-5j33-cvvr-w245): Apache Tomcat Time-of-check Time-of-use (TOCTOU) Race Condition vulnerability

Severity: HIGH

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat:tomcat-catalina to 11.0.2 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 10.1.34 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 9.0.98 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.2 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.34 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.98 or later

### CVE-2024-56337: Apache Tomcat Time-of-check Time-of-use (TOCTOU) Race Condition vulnerability

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2024-56337](https://github.com/advisories/GHSA-27hp-xhwr-wr2m): Apache Tomcat Time-of-check Time-of-use (TOCTOU) Race Condition vulnerability

Severity: HIGH

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat:tomcat-catalina to 11.0.2 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 10.1.34 or later
  - Upgrade org.apache.tomcat:tomcat-embed-core to 9.0.98 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.2 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.34 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.98 or later

### CVE-2025-24813: Apache Tomcat: Potential RCE and/or information disclosure and/or information corruption with partial PUT

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2025-24813](https://github.com/advisories/GHSA-83qj-6fr2-vhqg): Apache Tomcat: Potential RCE and/or information disclosure and/or information corruption with partial PUT

Severity: CRITICAL

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat:tomcat-catalina to 11.0.3 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 10.1.35 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 9.0.99 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.3 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.35 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.99 or later

### CVE-2025-48988: Apache Tomcat - DoS in multipart upload

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2025-48988](https://github.com/advisories/GHSA-h3gc-qfqq-6h8f): Apache Tomcat - DoS in multipart upload

Severity: HIGH

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat:tomcat-catalina to 11.0.8 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 10.1.42 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 9.0.106 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.8 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.42 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.106 or later

### CVE-2025-52520: Apache Tomcat Catalina is vulnerable to DoS attack through bypassing of size limits

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2025-52520](https://github.com/advisories/GHSA-wr62-c79q-cv37): Apache Tomcat Catalina is vulnerable to DoS attack through bypassing of size limits

Severity: HIGH

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat:tomcat-catalina to 11.0.9 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 10.1.43 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 9.0.107 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.9 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.43 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.107 or later

### CVE-2025-53506: Apache Tomcat Coyote vulnerable to Denial of Service via excessive HTTP/2 streams

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2025-53506](https://github.com/advisories/GHSA-25xr-qj8w-c4vf): Apache Tomcat Coyote vulnerable to Denial of Service via excessive HTTP/2 streams

Severity: HIGH

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat:tomcat-coyote to 11.0.9 or later
  - Upgrade org.apache.tomcat:tomcat-coyote to 10.1.43 or later
  - Upgrade org.apache.tomcat:tomcat-coyote to 9.0.107 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.107 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.43 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.9 or later

### CVE-2025-48989: Apache Tomcat Improper Resource Shutdown or Release vulnerability

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2025-48989](https://github.com/advisories/GHSA-gqp3-2cvr-x8m3): Apache Tomcat Improper Resource Shutdown or Release vulnerability

Severity: HIGH

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat:tomcat-coyote to 11.0.10 or later
  - Upgrade org.apache.tomcat:tomcat-coyote to 10.1.44 or later
  - Upgrade org.apache.tomcat:tomcat-coyote to 9.0.108 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.10 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.44 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.108 or later

### CVE-2025-55752: Apache Tomcat Vulnerable to Relative Path Traversal

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2025-55752](https://github.com/advisories/GHSA-wmwf-9ccg-fff5): Apache Tomcat Vulnerable to Relative Path Traversal

Severity: HIGH

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat:tomcat to 11.0.11 or later
  - Upgrade org.apache.tomcat:tomcat to 10.1.45 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 11.0.11 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 10.1.45 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.11 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.45 or later
  - Upgrade org.apache.tomcat:tomcat to 9.0.109 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 9.0.109 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.109 or later

### CVE-2026-24734: Apache Tomcat has an Improper Input Validation vulnerability

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2026-24734](https://github.com/advisories/GHSA-mgp5-rv84-w37q): Apache Tomcat has an Improper Input Validation vulnerability

Severity: HIGH

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat:tomcat-coyote to 11.0.18 or later
  - Upgrade org.apache.tomcat:tomcat-coyote to 10.1.52 or later
  - Upgrade org.apache.tomcat:tomcat-coyote to 9.0.115 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.18 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.52 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.115 or later
  - Upgrade org.apache.tomcat:tomcat-coyote-ffm to 11.0.18 or later
  - Upgrade org.apache.tomcat:tomcat-coyote-ffm to 10.1.52 or later
  - Upgrade org.apache.tomcat:tomcat-coyote-ffm to 9.0.115 or later

### CVE-2026-24880: Apache Tomcat has an HTTP Request/Response Smuggling vulnerability

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2026-24880](https://github.com/advisories/GHSA-563x-q5rq-57qp): Apache Tomcat has an HTTP Request/Response Smuggling vulnerability

Severity: HIGH

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat:tomcat-coyote to 9.0.116 or later
  - Upgrade org.apache.tomcat:tomcat-coyote to 10.1.52 or later
  - Upgrade org.apache.tomcat:tomcat-coyote to 11.0.20 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.116 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.52 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.20 or later

### CVE-2026-34487: Apache Tomcat vulnerable to Insertion of Sensitive Information into Log File

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2026-34487](https://github.com/advisories/GHSA-x4m4-345f-5h5g): Apache Tomcat vulnerable to Insertion of Sensitive Information into Log File

Severity: HIGH

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat:tomcat to 9.0.117 or later
  - Upgrade org.apache.tomcat:tomcat to 10.1.54 or later
  - Upgrade org.apache.tomcat:tomcat to 11.0.21 or later
  - Upgrade org.apache.tomcat:tomcat-tribes to 9.0.117 or later
  - Upgrade org.apache.tomcat:tomcat-tribes to 10.1.54 or later
  - Upgrade org.apache.tomcat:tomcat-tribes to 11.0.21 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.117 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.54 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.21 or later

### CVE-2026-34483: Apache Tomcat has an Improper Encoding or Escaping of Output vulnerability in the JsonAccessLogValve

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2026-34483](https://github.com/advisories/GHSA-rv64-5gf8-9qq8): Apache Tomcat has an Improper Encoding or Escaping of Output vulnerability in the JsonAccessLogValve

Severity: HIGH

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat:tomcat-catalina to 9.0.116 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 10.1.54 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 11.0.21 or later
  - Upgrade org.apache.tomcat:tomcat to 9.0.116 or later
  - Upgrade org.apache.tomcat:tomcat to 10.1.54 or later
  - Upgrade org.apache.tomcat:tomcat to 11.0.21 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.116 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.54 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.21 or later

### CVE-2026-42498: Apache Tomcat - WebSocket authentication header exposure

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2026-42498](https://github.com/advisories/GHSA-fv25-8xcx-gqjc): Apache Tomcat - WebSocket authentication header exposure

Severity: HIGH

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.118 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.55 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.22 or later
  - Upgrade org.apache.tomcat:tomcat to 9.0.118 or later
  - Upgrade org.apache.tomcat:tomcat to 10.1.55 or later
  - Upgrade org.apache.tomcat:tomcat to 11.0.22 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 9.0.118 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 10.1.55 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 11.0.22 or later

### CVE-2026-41293: Apache Tomcat - HTTP/2 request headers not validated

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2026-41293](https://github.com/advisories/GHSA-r29c-68gh-xp6x): Apache Tomcat - HTTP/2 request headers not validated

Severity: CRITICAL

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.55 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.22 or later
  - Upgrade org.apache.tomcat:tomcat to 10.1.55 or later
  - Upgrade org.apache.tomcat:tomcat to 11.0.22 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.118 or later
  - Upgrade org.apache.tomcat:tomcat to 9.0.118 or later
  - Upgrade org.apache.tomcat:tomcat-coyote to 9.0.118 or later
  - Upgrade org.apache.tomcat:tomcat-coyote to 10.1.55 or later
  - Upgrade org.apache.tomcat:tomcat-coyote to 11.0.22 or later

### CVE-2026-43515: Apache Tomcat - Security constraints not correctly applied

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2026-43515](https://github.com/advisories/GHSA-5m62-pw8w-7w9f): Apache Tomcat - Security constraints not correctly applied

Severity: CRITICAL

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.118 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.55 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.22 or later
  - Upgrade org.apache.tomcat:tomcat to 9.0.118 or later
  - Upgrade org.apache.tomcat:tomcat to 10.1.55 or later
  - Upgrade org.apache.tomcat:tomcat to 11.0.22 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 9.0.118 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 10.1.55 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 11.0.22 or later

### CVE-2026-43513: Apache Tomcat: LockOutRealm treats user names as case-sensitive

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2026-43513](https://github.com/advisories/GHSA-5mp6-jrq3-r938): Apache Tomcat: LockOutRealm treats user names as case-sensitive

Severity: HIGH

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.118 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.55 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.22 or later
  - Upgrade org.apache.tomcat:tomcat to 9.0.118 or later
  - Upgrade org.apache.tomcat:tomcat to 10.1.55 or later
  - Upgrade org.apache.tomcat:tomcat to 11.0.22 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 9.0.118 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 10.1.55 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 11.0.22 or later

### CVE-2026-43512: Apache Tomcat - Digest authenticator will authenticate any unknown user

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2026-43512](https://github.com/advisories/GHSA-h6fc-48rj-7qqh): Apache Tomcat - Digest authenticator will authenticate any unknown user

Severity: CRITICAL

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.118 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.55 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.22 or later
  - Upgrade org.apache.tomcat:tomcat to 9.0.118 or later
  - Upgrade org.apache.tomcat:tomcat to 10.1.55 or later
  - Upgrade org.apache.tomcat:tomcat to 11.0.22 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 9.0.118 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 10.1.55 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 11.0.22 or later

### CVE-2026-41284: Apache Tomcat: Unbounded read in WebDAV LOCK and  PROPFIND handling

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2026-41284](https://github.com/advisories/GHSA-gx5v-xp9w-j4cg): Apache Tomcat: Unbounded read in WebDAV LOCK and  PROPFIND handling

Severity: HIGH

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.118 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.55 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.22 or later
  - Upgrade org.apache.tomcat:tomcat to 9.0.118 or later
  - Upgrade org.apache.tomcat:tomcat to 10.1.55 or later
  - Upgrade org.apache.tomcat:tomcat to 11.0.22 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 9.0.118 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 10.1.55 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 11.0.22 or later

### CVE-2026-53404: Apache Tomcat's rewrite valve has an Always-Incorrect Control Flow Implementation vulnerability

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2026-53404](https://github.com/advisories/GHSA-h792-v28v-ppgr): Apache Tomcat's rewrite valve has an Always-Incorrect Control Flow Implementation vulnerability

Severity: HIGH

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.23 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.56 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.119 or later
  - Upgrade org.apache.tomcat:tomcat to 11.0.23 or later
  - Upgrade org.apache.tomcat:tomcat to 10.1.56 or later
  - Upgrade org.apache.tomcat:tomcat to 9.0.119 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 11.0.23 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 10.1.56 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 9.0.119 or later

### CVE-2026-55276: Apache Tomcat has an Always-Incorrect Control Flow Implementation vulnerability

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2026-55276](https://github.com/advisories/GHSA-mqg3-r7h5-24x4): Apache Tomcat has an Always-Incorrect Control Flow Implementation vulnerability

Severity: CRITICAL

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.23 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.56 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.119 or later
  - Upgrade org.apache.tomcat:tomcat to 11.0.23 or later
  - Upgrade org.apache.tomcat:tomcat to 10.1.56 or later
  - Upgrade org.apache.tomcat:tomcat to 9.0.119 or later
  - Upgrade org.apache.tomcat:tomcat-util-scan to 11.0.23 or later
  - Upgrade org.apache.tomcat:tomcat-util-scan to 10.1.56 or later
  - Upgrade org.apache.tomcat:tomcat-util-scan to 9.0.119 or later

### CVE-2026-55957: Apache Tomcat has a Missing Critical Step in Authentication vulnerability

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2026-55957](https://github.com/advisories/GHSA-7895-gffq-w6jq): Apache Tomcat has a Missing Critical Step in Authentication vulnerability

Severity: HIGH

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.5 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.37 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.101 or later
  - Upgrade org.apache.tomcat:tomcat to 11.0.5 or later
  - Upgrade org.apache.tomcat:tomcat to 10.1.37 or later
  - Upgrade org.apache.tomcat:tomcat to 9.0.101 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 11.0.5 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 10.1.37 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 9.0.101 or later

### CVE-2026-68525: Apache Tomcat's FORM authentication process has an Incorrect Authorization vulnerability

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2026-68525](https://github.com/advisories/GHSA-h3x4-894j-xpx5): Apache Tomcat's FORM authentication process has an Incorrect Authorization vulnerability

Severity: CRITICAL

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat:tomcat to 11.0.25 or later
  - Upgrade org.apache.tomcat:tomcat to 10.1.58 or later
  - Upgrade org.apache.tomcat:tomcat to 9.0.121 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 11.0.25 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 10.1.58 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 9.0.121 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.25 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.58 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.121 or later

### CVE-2026-65182: Apache Tomcat has an Improper Access Control, Incorrect Authorization vulnerability

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2026-65182](https://github.com/advisories/GHSA-gcx9-497g-6cp6): Apache Tomcat has an Improper Access Control, Incorrect Authorization vulnerability

Severity: CRITICAL

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat:tomcat to 11.0.25 or later
  - Upgrade org.apache.tomcat:tomcat to 10.1.58 or later
  - Upgrade org.apache.tomcat:tomcat to 9.0.121 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 11.0.25 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 10.1.58 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 9.0.121 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.25 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.58 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.121 or later

### CVE-2026-65905: Apache Tomcat's DIGEST authenticator has an Authentication Bypass by Capture-replay vulnerability

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2026-65905](https://github.com/advisories/GHSA-9xv2-5v5q-p794): Apache Tomcat's DIGEST authenticator has an Authentication Bypass by Capture-replay vulnerability

Severity: CRITICAL

Affected dependencies:
  - org.apache.tomcat.embed:tomcat-embed-core:9.0.83 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.apache.tomcat:tomcat to 11.0.25 or later
  - Upgrade org.apache.tomcat:tomcat to 10.1.58 or later
  - Upgrade org.apache.tomcat:tomcat to 9.0.121 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 11.0.25 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 10.1.58 or later
  - Upgrade org.apache.tomcat.embed:tomcat-embed-core to 9.0.121 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 11.0.25 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 10.1.58 or later
  - Upgrade org.apache.tomcat:tomcat-catalina to 9.0.121 or later

### CVE-2016-1000027: Pivotal Spring Framework contains unsafe Java deserialization methods

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2016-1000027](https://github.com/advisories/GHSA-4wrc-f8pq-fpqp): Pivotal Spring Framework contains unsafe Java deserialization methods

Severity: CRITICAL

Affected dependencies:
  - org.springframework:spring-web:5.3.31 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.springframework:spring-web to 6.0.0 or later

### CVE-2024-22243: Spring Web vulnerable to Open Redirect or Server Side Request Forgery

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2024-22243](https://github.com/advisories/GHSA-ccgv-vj62-xf9h): Spring Web vulnerable to Open Redirect or Server Side Request Forgery

Severity: HIGH

Affected dependencies:
  - org.springframework:spring-web:5.3.31 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.springframework:spring-web to 6.1.4 or later
  - Upgrade org.springframework:spring-web to 6.0.17 or later
  - Upgrade org.springframework:spring-web to 5.3.32 or later

### CVE-2024-22259: Spring Framework URL Parsing with Host Validation Vulnerability

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2024-22259](https://github.com/advisories/GHSA-hgjh-9rj2-g67j): Spring Framework URL Parsing with Host Validation Vulnerability

Severity: HIGH

Affected dependencies:
  - org.springframework:spring-web:5.3.31 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.springframework:spring-web to 6.1.5 or later
  - Upgrade org.springframework:spring-web to 6.0.18 or later
  - Upgrade org.springframework:spring-web to 5.3.33 or later

### CVE-2024-22262: Spring Framework URL Parsing with Host Validation

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2024-22262](https://github.com/advisories/GHSA-2wrp-6fg6-hmc5): Spring Framework URL Parsing with Host Validation

Severity: HIGH

Affected dependencies:
  - org.springframework:spring-web:5.3.31 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.springframework:spring-web to 5.3.34 or later
  - Upgrade org.springframework:spring-web to 6.0.19 or later
  - Upgrade org.springframework:spring-web to 6.1.6 or later

### CVE-2024-38816: Path traversal vulnerability in functional web frameworks

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2024-38816](https://github.com/advisories/GHSA-cx7f-g6mp-7hqm): Path traversal vulnerability in functional web frameworks

Severity: HIGH

Affected dependencies:
  - org.springframework:spring-webmvc:5.3.31 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.springframework:spring-webmvc to 6.1.13 or later
  - Upgrade org.springframework:spring-webflux to 6.1.13 or later

### CVE-2024-38819: Spring Framework Path Traversal vulnerability

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2024-38819](https://github.com/advisories/GHSA-g5vr-rgqm-vf78): Spring Framework Path Traversal vulnerability

Severity: HIGH

Affected dependencies:
  - org.springframework:spring-webmvc:5.3.31 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.springframework:spring-webflux to 6.1.14 or later
  - Upgrade org.springframework:spring-webmvc to 6.1.14 or later

### CVE-2026-41842: Spring Framework Denial of Service via Versioned Resources in Spring MVC and WebFlux

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2026-41842](https://github.com/advisories/GHSA-x23c-287f-qqv5): Spring Framework Denial of Service via Versioned Resources in Spring MVC and WebFlux

Severity: HIGH

Affected dependencies:
  - org.springframework:spring-webmvc:5.3.31 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.springframework:spring-webmvc to 7.0.8 or later
  - Upgrade org.springframework:spring-webflux to 7.0.8 or later
  - Upgrade org.springframework:spring-webmvc to 6.2.19 or later
  - Upgrade org.springframework:spring-webflux to 6.2.19 or later

### CVE-2026-41845: Spring Framework Cross-site Scripting via JavaScriptUtils

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2026-41845](https://github.com/advisories/GHSA-3chg-m5w7-qfv5): Spring Framework Cross-site Scripting via JavaScriptUtils

Severity: HIGH

Affected dependencies:
  - org.springframework:spring-webmvc:5.3.31 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.springframework:spring-webmvc to 7.0.8 or later
  - Upgrade org.springframework:spring-webmvc to 6.2.19 or later

### CVE-2026-47884: Spring Framework Improper Path Limitation in XsltView

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2026-47884](https://github.com/advisories/GHSA-pc63-qcmh-9cmg): Spring Framework Improper Path Limitation in XsltView

Severity: CRITICAL

Affected dependencies:
  - org.springframework:spring-webmvc:5.3.31 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.springframework:spring-webmvc to 7.0.9 or later

### CVE-2026-41849: Spring Framework Denial of Service via Integer Overflow in SpEL Expressions

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2026-41849](https://github.com/advisories/GHSA-775g-4xr8-78h8): Spring Framework Denial of Service via Integer Overflow in SpEL Expressions

Severity: HIGH

Affected dependencies:
  - org.springframework:spring-expression:5.3.31 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

### CVE-2026-41850: Spring Framework Algorithmic Denial of Service via SpEL Expressions

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:25

[CVE-2026-41850](https://github.com/advisories/GHSA-r5w3-xv2f-j59q): Spring Framework Algorithmic Denial of Service via SpEL Expressions

Severity: HIGH

Affected dependencies:
  - org.springframework:spring-expression:5.3.31 (transitive, pulled by org.springframework.boot:spring-boot-starter-web:2.7.18 at web/pom.xml:25)

Recommended fix:
  - Upgrade org.springframework:spring-expression to 7.0.8 or later
  - Upgrade org.springframework:spring-expression to 6.2.19 or later

### CVE-2026-69220: RabbitMQ Java client ValueReader: Unbounded recursive table/array nesting causes StackOverflowError DoS

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:29, worker/pom.xml:25

[CVE-2026-69220](https://github.com/advisories/GHSA-93j5-89vc-pph4): RabbitMQ Java client ValueReader: Unbounded recursive table/array nesting causes StackOverflowError DoS

Severity: HIGH

Affected dependencies:
  - com.rabbitmq:amqp-client:5.14.3 (transitive, pulled by org.springframework.boot:spring-boot-starter-amqp:2.7.18 at web/pom.xml:29, worker/pom.xml:25)

Recommended fix:
  - Upgrade com.rabbitmq:amqp-client to 5.33.1 or later

### CVE-2026-69219: RabbitMQ Java client ValueReader: Oversized LongString/bytes length triggers OOM via unchecked allocation

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:29, worker/pom.xml:25

[CVE-2026-69219](https://github.com/advisories/GHSA-68mj-5wr7-6fgg): RabbitMQ Java client ValueReader: Oversized LongString/bytes length triggers OOM via unchecked allocation

Severity: HIGH

Affected dependencies:
  - com.rabbitmq:amqp-client:5.14.3 (transitive, pulled by org.springframework.boot:spring-boot-starter-amqp:2.7.18 at web/pom.xml:29, worker/pom.xml:25)

Recommended fix:
  - Upgrade com.rabbitmq:amqp-client to 5.33.1 or later

### CVE-2026-63337: RabbitMQ Java client: Unvalidated Class.forName in JSON-RPC ProcedureDescription enables arbitrary class loading

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:29, worker/pom.xml:25

[CVE-2026-63337](https://github.com/advisories/GHSA-6g32-pxv4-2wfj): RabbitMQ Java client: Unvalidated Class.forName in JSON-RPC ProcedureDescription enables arbitrary class loading

Severity: HIGH

Affected dependencies:
  - com.rabbitmq:amqp-client:5.14.3 (transitive, pulled by org.springframework.boot:spring-boot-starter-amqp:2.7.18 at web/pom.xml:29, worker/pom.xml:25)

Recommended fix:
  - Upgrade com.rabbitmq:amqp-client to 5.33.0 or later

### CVE-2026-75516: RabbitMQ Java client has frame-level OOM: Math.min(maxInboundMessageBodySize, 0) defeats frame size enforcement

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:29, worker/pom.xml:25

[CVE-2026-75516](https://github.com/advisories/GHSA-jh4v-gfqj-7rhx): RabbitMQ Java client has frame-level OOM: Math.min(maxInboundMessageBodySize, 0) defeats frame size enforcement

Severity: HIGH

Affected dependencies:
  - com.rabbitmq:amqp-client:5.14.3 (transitive, pulled by org.springframework.boot:spring-boot-starter-amqp:2.7.18 at web/pom.xml:29, worker/pom.xml:25)

Recommended fix:
  - Upgrade com.rabbitmq:amqp-client to 5.34.0 or later

### CVE-2026-33870: Netty: HTTP Request Smuggling via Chunked Extension Quoted-String Parsing

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60

[CVE-2026-33870](https://github.com/advisories/GHSA-pwqr-wmgm-9rr8): Netty: HTTP Request Smuggling via Chunked Extension Quoted-String Parsing

Severity: HIGH

Affected dependencies:
  - io.netty:netty-codec-http:4.1.101.Final (transitive, pulled by software.amazon.awssdk:s3:2.25.13 at web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60)

Recommended fix:
  - Upgrade io.netty:netty-codec-http to 4.1.132.Final or later
  - Upgrade io.netty:netty-codec-http to 4.2.10.Final or later

### CVE-2026-42584: Netty has HttpClientCodec response desynchronization

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60

[CVE-2026-42584](https://github.com/advisories/GHSA-57rv-r2g8-2cj3): Netty has HttpClientCodec response desynchronization

Severity: HIGH

Affected dependencies:
  - io.netty:netty-codec-http:4.1.101.Final (transitive, pulled by software.amazon.awssdk:s3:2.25.13 at web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60)

Recommended fix:
  - Upgrade io.netty:netty-codec-http to 4.2.13.Final or later
  - Upgrade io.netty:netty-codec-http to 4.1.133.Final or later

### CVE-2026-42587: Netty: HttpContentDecompressor maxAllocation bypass when Content-Encoding set to br/zstd/snappy leads to decompression bomb DoS

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60

[CVE-2026-42587](https://github.com/advisories/GHSA-f6hv-jmp6-3vwv): Netty: HttpContentDecompressor maxAllocation bypass when Content-Encoding set to br/zstd/snappy leads to decompression bomb DoS

Severity: HIGH

Affected dependencies:
  - io.netty:netty-codec-http:4.1.101.Final (transitive, pulled by software.amazon.awssdk:s3:2.25.13 at web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60)
  - io.netty:netty-codec-http2:4.1.101.Final (transitive, pulled by software.amazon.awssdk:s3:2.25.13 at web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60)

Recommended fix:
  - Upgrade io.netty:netty-codec-http to 4.2.13.Final or later
  - Upgrade io.netty:netty-codec-http2 to 4.2.13.Final or later
  - Upgrade io.netty:netty-codec-http to 4.1.133.Final or later
  - Upgrade io.netty:netty-codec-http2 to 4.1.133.Final or later

### CVE-2026-55831: Netty SPDY SETTINGS frame count materializes unbounded settings map

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60

[CVE-2026-55831](https://github.com/advisories/GHSA-6jqx-86gh-f27w): Netty SPDY SETTINGS frame count materializes unbounded settings map

Severity: HIGH

Affected dependencies:
  - io.netty:netty-codec-http:4.1.101.Final (transitive, pulled by software.amazon.awssdk:s3:2.25.13 at web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60)

Recommended fix:
  - Upgrade io.netty:netty-codec-http to 4.2.16.Final or later
  - Upgrade io.netty:netty-codec-http to 4.1.136.Final or later

### CVE-2026-55833: Netty SPDY zlib header block continues decoded expansion after maxHeaderSize truncation

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60

[CVE-2026-55833](https://github.com/advisories/GHSA-mvh2-crg5-v77c): Netty SPDY zlib header block continues decoded expansion after maxHeaderSize truncation

Severity: HIGH

Affected dependencies:
  - io.netty:netty-codec-http:4.1.101.Final (transitive, pulled by software.amazon.awssdk:s3:2.25.13 at web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60)

Recommended fix:
  - Upgrade io.netty:netty-codec-http to 4.2.16.Final or later
  - Upgrade io.netty:netty-codec-http to 4.1.136.Final or later

### CVE-2026-56745: Netty: [SpdyHttpDecoder] ByteBuf Reference Leak on RST_STREAM Leads to Native Memory Exhaustion

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60

[CVE-2026-56745](https://github.com/advisories/GHSA-jppx-w49h-x2qq): Netty: [SpdyHttpDecoder] ByteBuf Reference Leak on RST_STREAM Leads to Native Memory Exhaustion

Severity: HIGH

Affected dependencies:
  - io.netty:netty-codec-http:4.1.101.Final (transitive, pulled by software.amazon.awssdk:s3:2.25.13 at web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60)

Recommended fix:
  - Upgrade io.netty:netty-codec-http to 4.2.16.Final or later
  - Upgrade io.netty:netty-codec-http to 4.1.136.Final or later

### CVE-2025-55163: Netty affected by MadeYouReset HTTP/2 DDoS vulnerability

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60

[CVE-2025-55163](https://github.com/advisories/GHSA-prj3-ccx8-p6x4): Netty affected by MadeYouReset HTTP/2 DDoS vulnerability

Severity: HIGH

Affected dependencies:
  - io.netty:netty-codec-http2:4.1.101.Final (transitive, pulled by software.amazon.awssdk:s3:2.25.13 at web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60)

Recommended fix:
  - Upgrade io.netty:netty-codec-http2 to 4.2.4.Final or later
  - Upgrade io.netty:netty-codec-http2 to 4.1.124.Final or later
  - Upgrade io.grpc:grpc-netty-shaded to 1.75.0 or later

### CVE-2026-33871: Netty HTTP/2 CONTINUATION Frame Flood DoS via Zero-Byte Frame Bypass

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60

[CVE-2026-33871](https://github.com/advisories/GHSA-w9fj-cfpg-grvv): Netty HTTP/2 CONTINUATION Frame Flood DoS via Zero-Byte Frame Bypass

Severity: HIGH

Affected dependencies:
  - io.netty:netty-codec-http2:4.1.101.Final (transitive, pulled by software.amazon.awssdk:s3:2.25.13 at web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60)

Recommended fix:
  - Upgrade io.netty:netty-codec-http2 to 4.1.132.Final or later
  - Upgrade io.netty:netty-codec-http2 to 4.2.11.Final or later

### CVE-2026-56819: Netty: HTTP/2 decompression leaks ByteBuf reference count when the decompressor channel is already closed (Direct memory leak / OOM DoS)

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60

[CVE-2026-56819](https://github.com/advisories/GHSA-93wv-jw9v-4972): Netty: HTTP/2 decompression leaks ByteBuf reference count when the decompressor channel is already closed (Direct memory leak / OOM DoS)

Severity: HIGH

Affected dependencies:
  - io.netty:netty-codec-http2:4.1.101.Final (transitive, pulled by software.amazon.awssdk:s3:2.25.13 at web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60)

Recommended fix:
  - Upgrade io.netty:netty-codec-http2 to 4.2.16.Final or later
  - Upgrade io.netty:netty-codec-http2 to 4.1.136.Final or later

### CVE-2026-42583: Netty Lz4FrameDecoder is vulnerable to resource exhaustion 

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60

[CVE-2026-42583](https://github.com/advisories/GHSA-mj4r-2hfc-f8p6): Netty Lz4FrameDecoder is vulnerable to resource exhaustion 

Severity: HIGH

Affected dependencies:
  - io.netty:netty-codec:4.1.101.Final (transitive, pulled by software.amazon.awssdk:s3:2.25.13 at web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60)

Recommended fix:
  - Upgrade io.netty:netty-codec-compression to 4.2.13.Final or later
  - Upgrade io.netty:netty-codec to 4.1.133.Final or later

### CVE-2026-59901: Netty: [Bzip2Decoder] Infinite Loop in RLE State Machine Leads to Event-Loop Thread Hang

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60

[CVE-2026-59901](https://github.com/advisories/GHSA-558v-64gr-wgg4): Netty: [Bzip2Decoder] Infinite Loop in RLE State Machine Leads to Event-Loop Thread Hang

Severity: HIGH

Affected dependencies:
  - io.netty:netty-codec:4.1.101.Final (transitive, pulled by software.amazon.awssdk:s3:2.25.13 at web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60)

Recommended fix:
  - Upgrade io.netty:netty-codec-compression to 4.2.16.Final or later
  - Upgrade io.netty:netty-codec to 4.1.136.Final or later

### CVE-2025-24970: SslHandler doesn't correctly validate packets which can lead to native crash when using native SSLEngine

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60

[CVE-2025-24970](https://github.com/advisories/GHSA-4g8c-wm8x-jfhw): SslHandler doesn't correctly validate packets which can lead to native crash when using native SSLEngine

Severity: HIGH

Affected dependencies:
  - io.netty:netty-handler:4.1.101.Final (transitive, pulled by software.amazon.awssdk:s3:2.25.13 at web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60)

Recommended fix:
  - Upgrade io.netty:netty-handler to 4.1.118.Final or later

### CVE-2026-44249: Netty has an IPv6 Subnet Filter Bypass via Incorrect Comparator Masking

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60

[CVE-2026-44249](https://github.com/advisories/GHSA-3qp7-7mw8-wx86): Netty has an IPv6 Subnet Filter Bypass via Incorrect Comparator Masking

Severity: HIGH

Affected dependencies:
  - io.netty:netty-handler:4.1.101.Final (transitive, pulled by software.amazon.awssdk:s3:2.25.13 at web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60)

Recommended fix:
  - Upgrade io.netty:netty-handler to 4.2.15.Final or later
  - Upgrade io.netty:netty-handler to 4.1.135.Final or later

### CVE-2026-45416: Netty: SNI handler pre-allocates up to 16 MiB from nine attacker bytes

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60

[CVE-2026-45416](https://github.com/advisories/GHSA-x4gw-5cx5-pgmh): Netty: SNI handler pre-allocates up to 16 MiB from nine attacker bytes

Severity: HIGH

Affected dependencies:
  - io.netty:netty-handler:4.1.101.Final (transitive, pulled by software.amazon.awssdk:s3:2.25.13 at web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60)

Recommended fix:
  - Upgrade io.netty:netty-handler to 4.2.15.Final or later
  - Upgrade io.netty:netty-handler to 4.1.135.Final or later

### CVE-2026-50010: Netty: Wrapping plain trust manager silently disables hostname verification

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60

[CVE-2026-50010](https://github.com/advisories/GHSA-c653-97m9-rcg9): Netty: Wrapping plain trust manager silently disables hostname verification

Severity: HIGH

Affected dependencies:
  - io.netty:netty-handler:4.1.101.Final (transitive, pulled by software.amazon.awssdk:s3:2.25.13 at web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60)

Recommended fix:
  - Upgrade io.netty:netty-handler to 4.2.15.Final or later
  - Upgrade io.netty:netty-handler to 4.1.135.Final or later

### CVE-2026-75595: Netty: SNI Routing Bypass via Fragmented TLS ClientHello Causing Fallback to Default SslContext

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60

[CVE-2026-75595](https://github.com/advisories/GHSA-c4c3-7fpv-j4q5): Netty: SNI Routing Bypass via Fragmented TLS ClientHello Causing Fallback to Default SslContext

Severity: CRITICAL

Affected dependencies:
  - io.netty:netty-handler:4.1.101.Final (transitive, pulled by software.amazon.awssdk:s3:2.25.13 at web/pom.xml:33, web/pom.xml:71, worker/pom.xml:29, worker/pom.xml:60)

Recommended fix:
  - Upgrade io.netty:netty-handler to 4.2.17.Final or later
  - Upgrade io.netty:netty-handler to 4.1.137.Final or later

### CVE-2026-40972: Spring Boot DevTools remote secret comparison is vulnerable to timing attacks

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:37

[CVE-2026-40972](https://github.com/advisories/GHSA-56v8-86gj-66jp): Spring Boot DevTools remote secret comparison is vulnerable to timing attacks

Severity: HIGH

Affected dependencies:
  - org.springframework.boot:spring-boot-devtools:2.7.18 (declared at web/pom.xml:37)

Recommended fix:
  - Upgrade org.springframework.boot:spring-boot-devtools to 4.0.6 or later
  - Upgrade org.springframework.boot:spring-boot-devtools to 3.5.14 or later

### CVE-2025-22235: Spring Boot EndpointRequest.to() creates wrong matcher if actuator endpoint is not exposed

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:37

[CVE-2025-22235](https://github.com/advisories/GHSA-rc42-6c7j-7h5r): Spring Boot EndpointRequest.to() creates wrong matcher if actuator endpoint is not exposed

Severity: HIGH

Affected dependencies:
  - org.springframework.boot:spring-boot:2.7.18 (transitive, pulled by org.springframework.boot:spring-boot-devtools:2.7.18 at web/pom.xml:37)

Recommended fix:
  - Upgrade org.springframework.boot:spring-boot to 3.3.11 or later
  - Upgrade org.springframework.boot:spring-boot to 3.4.5 or later

### CVE-2026-40973: Spring Boot accepts predictable temp directory without ownership verification

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:37

[CVE-2026-40973](https://github.com/advisories/GHSA-wwpq-f5c3-7hvx): Spring Boot accepts predictable temp directory without ownership verification

Severity: HIGH

Affected dependencies:
  - org.springframework.boot:spring-boot:2.7.18 (transitive, pulled by org.springframework.boot:spring-boot-devtools:2.7.18 at web/pom.xml:37)

Recommended fix:
  - Upgrade org.springframework.boot:spring-boot to 4.0.6 or later
  - Upgrade org.springframework.boot:spring-boot to 3.5.14 or later

### CVE-2026-24400: AssertJ has XML External Entity (XXE) vulnerability when parsing untrusted XML via isXmlEqualTo assertion

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:53, worker/pom.xml:38

[CVE-2026-24400](https://github.com/advisories/GHSA-rqfh-9r24-8c9r): AssertJ has XML External Entity (XXE) vulnerability when parsing untrusted XML via isXmlEqualTo assertion

Severity: HIGH

Affected dependencies:
  - org.assertj:assertj-core:3.22.0 (transitive, pulled by org.springframework.boot:spring-boot-starter-test:2.7.18 at web/pom.xml:53, worker/pom.xml:38)

Recommended fix:
  - Upgrade org.assertj:assertj-core to 3.27.7 or later

### CVE-2025-41249: Spring Framework annotation detection mechanism may result in improper authorization

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:53, worker/pom.xml:38

[CVE-2025-41249](https://github.com/advisories/GHSA-jmp9-x22r-554x): Spring Framework annotation detection mechanism may result in improper authorization

Severity: HIGH

Affected dependencies:
  - org.springframework:spring-core:5.3.31 (transitive, pulled by org.springframework.boot:spring-boot-starter-test:2.7.18 at web/pom.xml:53, worker/pom.xml:38)

Recommended fix:
  - Upgrade org.springframework:spring-core to 6.2.11 or later

### CVE-2026-41716: Spring Data Commons: Heap exhaustion from unbounded property-lookup cache retaining crafted string keys

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:58, worker/pom.xml:47

[CVE-2026-41716](https://github.com/advisories/GHSA-9fw2-h3hf-293r): Spring Data Commons: Heap exhaustion from unbounded property-lookup cache retaining crafted string keys

Severity: HIGH

Affected dependencies:
  - org.springframework.data:spring-data-commons:2.7.18 (transitive, pulled by org.springframework.boot:spring-boot-starter-data-jpa:2.7.18 at web/pom.xml:58, worker/pom.xml:47)

Recommended fix:
  - Upgrade org.springframework.data:spring-data-commons to 4.0.6 or later
  - Upgrade org.springframework.data:spring-data-commons to 3.5.12 or later

### CVE-2024-1597: org.postgresql:postgresql vulnerable to SQL Injection via line comment generation

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:62, worker/pom.xml:51

[CVE-2024-1597](https://github.com/advisories/GHSA-24rp-q3w6-vc56): org.postgresql:postgresql vulnerable to SQL Injection via line comment generation

Severity: CRITICAL

Affected dependencies:
  - org.postgresql:postgresql:42.3.8 (declared at web/pom.xml:62, worker/pom.xml:51)

Recommended fix:
  - Upgrade org.postgresql:postgresql to 42.2.28 or later
  - Upgrade org.postgresql:postgresql to 42.3.9 or later
  - Upgrade org.postgresql:postgresql to 42.4.4 or later
  - Upgrade org.postgresql:postgresql to 42.5.5 or later
  - Upgrade org.postgresql:postgresql to 42.6.1 or later
  - Upgrade org.postgresql:postgresql to 42.7.2 or later

### CVE-2026-42198: pgjdbc: Unbounded PBKDF2 iterations in SCRAM authentication allows CPU exhaustion DoS

- **Severity:** mandatory
- **Story Points:** 1
- **Files:** web/pom.xml:62, worker/pom.xml:51

[CVE-2026-42198](https://github.com/advisories/GHSA-98qh-xjc8-98pq): pgjdbc: Unbounded PBKDF2 iterations in SCRAM authentication allows CPU exhaustion DoS

Severity: HIGH

Affected dependencies:
  - org.postgresql:postgresql:42.3.8 (declared at web/pom.xml:62, worker/pom.xml:51)

Recommended fix:
  - Upgrade org.postgresql:postgresql to 42.7.11 or later

## CWE Findings (Code-Level Vulnerabilities)

### CWE-477: Use of Obsolete Function

- **Category:** Code Quality
- **Severity:** optional
- **Story Points:** 1
- **Files:** web/src/main/java/com/microsoft/migration/assets/config/WebMvcConfig.java

> The WebMvcConfigurer implementation in WebMvcConfig extends deprecated WebMvcConfigurerAdapter, and its nested interceptor extends deprecated HandlerInterceptorAdapter.

### CWE-681: Incorrect Conversion between Numeric Types

- **Category:** Code Quality
- **Severity:** potential
- **Story Points:** 3
- **Files:** worker/src/main/java/com/microsoft/migration/assets/worker/service/AbstractFileProcessingService.java

> In generateThumbnail, double-derived thumbnail dimensions are converted directly to int using (int) (maxDimension / aspectRatio) and (int) (maxDimension * aspectRatio). Extreme aspect ratios can truncate the result to zero, which is then passed to scaling and BufferedImage operations as an invalid dimension.

### CWE-682: Incorrect Calculation

- **Category:** Code Quality
- **Severity:** potential
- **Story Points:** 5
- **Files:** worker/src/main/java/com/microsoft/migration/assets/worker/service/AbstractFileProcessingService.java

> The generateThumbnail dimension calculation can yield zero-width or zero-height values for extreme image aspect ratios, after which progressiveScaling and scaleImage perform resource operations with invalid dimensions.

### CWE-772: Missing Release of Resource after Effective Lifetime

- **Category:** Code Quality
- **Severity:** potential
- **Story Points:** 3
- **Files:** worker/src/main/java/com/microsoft/migration/assets/worker/service/AbstractFileProcessingService.java

> generateThumbnail creates ImageOutputStream resources and closes them only in the normal success path after write and dispose operations. If writer setup or image writing throws, the stream and writer resources are not released by a try-with-resources or finally block.

### CWE-662: Improper Synchronization

- **Category:** Concurrency & Synchronization
- **Severity:** potential
- **Story Points:** 8
- **Files:** web/src/main/java/com/microsoft/migration/assets/service/LocalFileStorageService.java, worker/src/main/java/com/microsoft/migration/assets/worker/service/LocalFileProcessingService.java

> LocalFileStorageService.uploadObject() and deleteObject() (lines 95 and 124) overwrite or delete shared files under rootLocation while the web application is serving requests concurrently. LocalFileProcessingService.uploadThumbnail() (line 49) writes to the same rootLocation filename space without synchronization, so concurrent thumbnail writes, original uploads, and deletions can access the same exclusive file path simultaneously.

### CWE-820: Missing Synchronization

- **Category:** Concurrency & Synchronization
- **Severity:** potential
- **Story Points:** 8
- **Files:** web/src/main/java/com/microsoft/migration/assets/service/LocalFileStorageService.java, worker/src/main/java/com/microsoft/migration/assets/worker/service/LocalFileProcessingService.java

> Concurrent web requests use Files.copy(..., REPLACE_EXISTING) and Files.delete() on shared local storage paths (LocalFileStorageService lines 95 and 124), and the worker service writes thumbnails to derived paths (LocalFileProcessingService line 49) without any lock or synchronization mechanism.

### CWE-259: Use of Hard-coded Password

- **Category:** Credentials & Secrets
- **Severity:** optional
- **Story Points:** 5
- **Files:** scripts/startapp.sh, scripts/startapp.cmd

> The PostgreSQL startup scripts hard-code the password as POSTGRES_PASSWORD=postgres (scripts/startapp.sh line 11 and scripts/startapp.cmd line 9) for the database container's inbound authentication.

### CWE-798: Use of Hard-coded Credentials

- **Category:** Credentials & Secrets
- **Severity:** optional
- **Story Points:** 5
- **Files:** scripts/startapp.sh, scripts/startapp.cmd

> The PostgreSQL username and password are hard-coded together for container startup: POSTGRES_USER=postgres and POSTGRES_PASSWORD=postgres (scripts/startapp.sh lines 10-11 and scripts/startapp.cmd line 9).

### CWE-22: Improper Limitation of a Pathname to a Restricted Directory ('Path Traversal')

- **Category:** File & Path Security
- **Severity:** optional
- **Story Points:** 8
- **Files:** web/src/main/java/com/microsoft/migration/assets/service/LocalFileStorageService.java, web/src/main/java/com/microsoft/migration/assets/controller/S3Controller.java

> LocalFileStorageService resolves external names and keys directly under rootLocation without verifying the normalized result remains beneath the restricted directory. Upload uses originalFilename at lines 89-95, and get/delete use path variables as keys at lines 109-129; S3Controller exposes these operations through /view/{key} and /delete/{key} at lines 80-99.

### CWE-23: Relative Path Traversal

- **Category:** File & Path Security
- **Severity:** optional
- **Story Points:** 5
- **Files:** web/src/main/java/com/microsoft/migration/assets/service/LocalFileStorageService.java

> getObject, deleteObject, and thumbnail deletion at lines 109-129 call rootLocation.resolve(key) and do not normalize and enforce a rootLocation containment check. An external key containing relative traversal sequences can therefore resolve outside the storage directory.

### CWE-36: Absolute Path Traversal

- **Category:** File & Path Security
- **Severity:** optional
- **Story Points:** 5
- **Files:** web/src/main/java/com/microsoft/migration/assets/service/LocalFileStorageService.java

> The upload filename and get/delete keys are passed to Path.resolve at lines 94, 110, 120, and 129. Java Path.resolve treats an absolute external path as overriding rootLocation, and no absolute-path or containment validation is performed.

### CWE-434: Unrestricted Upload of File with Dangerous Type

- **Category:** File & Path Security
- **Severity:** mandatory
- **Story Points:** 8
- **Files:** web/src/main/java/com/microsoft/migration/assets/controller/S3Controller.java, web/src/main/java/com/microsoft/migration/assets/service/LocalFileStorageService.java, web/src/main/java/com/microsoft/migration/assets/service/AwsS3Service.java, worker/src/main/java/com/microsoft/migration/assets/worker/service/AbstractFileProcessingService.java

> The upload endpoint accepts any MultipartFile without an allowed extension or image/MIME allowlist. The file is stored by LocalFileStorageService or AwsS3Service and a processing message is emitted; AbstractFileProcessingService then automatically reads it with ImageIO.read and writes a thumbnail.

### CWE-99: Improper Control of Resource Identifiers ('Resource Injection')

- **Category:** Injection Attacks
- **Severity:** potential
- **Story Points:** 3
- **Files:** web/src/main/java/com/microsoft/migration/assets/service/LocalFileStorageService.java, worker/src/main/java/com/microsoft/migration/assets/worker/service/LocalFileProcessingService.java, web/src/main/java/com/microsoft/migration/assets/controller/S3Controller.java

> The externally controlled path variable key is used to construct and manipulate local file paths without confirming that the resolved path remains beneath rootLocation. In LocalFileStorageService, getObject() and deleteObject() call rootLocation.resolve(key) at lines 110 and 120, and LocalFileProcessingService uses rootLocation.resolve(key) for download and thumbnail paths at lines 38 and 47. S3Controller exposes key through @PathVariable and passes it to getObject/deleteObject at lines 80 and 97.

