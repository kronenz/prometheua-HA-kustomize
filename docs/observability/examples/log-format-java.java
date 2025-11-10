// Java 애플리케이션 로그 포맷 예제
// Logback + SLF4J를 사용한 JSON 로깅 설정

/*
 * SLF4J (Simple Logging Facade for Java)란?
 * - 로깅 프레임워크의 추상화 레이어 (인터페이스)
 * - 실제 구현체: Logback, Log4j2, JUL 등
 * - 장점: 구현체 교체 유연성, 라이브러리 호환성, 성능 최적화
 *
 * 왜 Logback을 사용하나?
 * - SLF4J 네이티브 구현 (가장 빠름)
 * - Spring Boot 기본 로깅 프레임워크
 * - 풍부한 기능 (필터, Appender, MDC 등)
 *
 * Log4j 1.x를 쓰지 않는 이유:
 * - 2015년 EOL (유지보수 중단)
 * - Log4Shell (CVE-2021-44228) 등 보안 취약점
 * - 성능 문제
 */

// 1. Maven 의존성 추가 (pom.xml)
/*
<dependency>
    <groupId>ch.qos.logback</groupId>
    <artifactId>logback-classic</artifactId>
    <version>1.4.14</version>
</dependency>
<dependency>
    <groupId>net.logstash.logback</groupId>
    <artifactId>logstash-logback-encoder</artifactId>
    <version>7.4</version>
</dependency>
<dependency>
    <groupId>org.slf4j</groupId>
    <artifactId>slf4j-api</artifactId>
    <version>2.0.9</version>
</dependency>
*/

// 2. Logback 설정 파일 (src/main/resources/logback.xml)
/*
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <encoder class="net.logstash.logback.encoder.LogstashEncoder">
            <!-- 커스텀 필드 추가 -->
            <customFields>{"app":"myapp","service-team":"myteam","environment":"production"}</customFields>
            <!-- 타임스탬프 포맷 -->
            <timestampPattern>yyyy-MM-dd'T'HH:mm:ss.SSS'Z'</timestampPattern>
            <!-- Exception stacktrace를 JSON 배열로 출력 -->
            <throwableConverter class="net.logstash.logback.stacktrace.ShortenedThrowableConverter">
                <maxDepthPerThrowable>30</maxDepthPerThrowable>
                <maxLength>2048</maxLength>
                <shortenedClassNameLength>20</shortenedClassNameLength>
            </throwableConverter>
        </encoder>
    </appender>

    <!-- 로그 레벨 설정 -->
    <root level="INFO">
        <appender-ref ref="CONSOLE" />
    </root>

    <!-- 패키지별 로그 레벨 설정 -->
    <logger name="com.mycompany.myapp" level="DEBUG" />
    <logger name="org.springframework" level="WARN" />
</configuration>
*/

// 3. 애플리케이션 코드 예제
package com.mycompany.myapp;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;

public class UserService {
    private static final Logger logger = LoggerFactory.getLogger(UserService.class);

    public void processUser(String userId) {
        // MDC를 사용하여 컨텍스트 정보 추가
        MDC.put("userId", userId);
        MDC.put("operation", "processUser");

        try {
            logger.info("Starting user processing");

            // 비즈니스 로직
            User user = fetchUser(userId);

            // 구조화된 로그 (추가 필드 포함)
            logger.info("User fetched successfully, username={}, email={}",
                       user.getUsername(), user.getEmail());

            validateUser(user);

            logger.info("User processing completed");

        } catch (UserNotFoundException e) {
            // 에러 로그 (Exception stacktrace 자동 포함)
            logger.error("User not found", e);
        } catch (ValidationException e) {
            logger.warn("User validation failed: {}", e.getMessage(), e);
        } catch (Exception e) {
            // 치명적 에러
            logger.error("Unexpected error during user processing", e);
            throw new RuntimeException("Failed to process user", e);
        } finally {
            // MDC 정리
            MDC.clear();
        }
    }

    // 로그 레벨별 사용 예제
    public void demonstrateLogLevels() {
        // DEBUG: 상세한 디버깅 정보 (개발 환경에서만 사용)
        logger.debug("Cache hit for key: {}", "user:123");

        // INFO: 일반적인 정보성 메시지
        logger.info("User login successful, userId={}", "user123");

        // WARN: 경고 (잠재적 문제, 서비스는 계속 동작)
        logger.warn("API rate limit approaching: {}/100 requests", 95);

        // ERROR: 에러 (기능 실패, 복구 가능)
        logger.error("Failed to send email notification, userId={}", "user123");

        // AUDIT: 감사 로그 (보안/컴플라이언스)
        MDC.put("log_type", "audit");
        logger.info("User password changed, userId={}, ip={}", "user123", "192.168.1.100");
        MDC.remove("log_type");
    }

    // 민감정보 마스킹 예제
    public void logWithMasking(String creditCard, String password) {
        // ❌ 잘못된 예: 민감정보를 그대로 로깅
        // logger.info("Payment processed, card={}", creditCard);

        // ✅ 올바른 예: 민감정보 마스킹
        String maskedCard = maskCreditCard(creditCard);
        logger.info("Payment processed, card={}", maskedCard);

        // ❌ 비밀번호는 절대 로깅하지 않음
        // logger.debug("User login, password={}", password);

        // ✅ 비밀번호는 로깅하지 않고 성공/실패만 기록
        logger.info("User login attempt, passwordProvided={}", password != null);
    }

    private String maskCreditCard(String card) {
        if (card == null || card.length() < 4) return "****";
        return "****-****-****-" + card.substring(card.length() - 4);
    }

    // Exception 처리 Best Practice
    private User fetchUser(String userId) throws UserNotFoundException {
        try {
            // 외부 API 호출 시뮬레이션
            return callExternalApi(userId);
        } catch (ApiException e) {
            // Exception chaining으로 전체 stacktrace 보존
            throw new UserNotFoundException("Failed to fetch user: " + userId, e);
        }
    }

    private User callExternalApi(String userId) throws ApiException {
        // API 호출 로직
        throw new ApiException("API timeout");
    }

    private void validateUser(User user) throws ValidationException {
        if (user.getEmail() == null) {
            throw new ValidationException("Email is required");
        }
    }
}

// 커스텀 Exception 클래스
class UserNotFoundException extends Exception {
    public UserNotFoundException(String message, Throwable cause) {
        super(message, cause);
    }
}

class ValidationException extends Exception {
    public ValidationException(String message) {
        super(message);
    }
}

class ApiException extends Exception {
    public ApiException(String message) {
        super(message);
    }
}

class User {
    private String username;
    private String email;

    public String getUsername() { return username; }
    public String getEmail() { return email; }
}

// 출력 예제 (JSON 형식)
/*
{
  "timestamp": "2025-01-15T08:30:45.123Z",
  "level": "INFO",
  "thread": "http-nio-8080-exec-1",
  "logger": "com.mycompany.myapp.UserService",
  "message": "User fetched successfully, username=john.doe, email=john@example.com",
  "app": "myapp",
  "service-team": "myteam",
  "environment": "production",
  "userId": "user123",
  "operation": "processUser"
}

{
  "timestamp": "2025-01-15T08:30:46.456Z",
  "level": "ERROR",
  "thread": "http-nio-8080-exec-1",
  "logger": "com.mycompany.myapp.UserService",
  "message": "User not found",
  "app": "myapp",
  "service-team": "myteam",
  "environment": "production",
  "userId": "user999",
  "operation": "processUser",
  "stack_trace": [
    "com.mycompany.myapp.UserNotFoundException: Failed to fetch user: user999",
    "\tat com.mycompany.myapp.UserService.fetchUser(UserService.java:45)",
    "\tat com.mycompany.myapp.UserService.processUser(UserService.java:20)",
    "Caused by: com.mycompany.myapp.ApiException: API timeout",
    "\tat com.mycompany.myapp.UserService.callExternalApi(UserService.java:78)",
    "\t... 2 more"
  ]
}
*/
