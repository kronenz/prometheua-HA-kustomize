"""
Python 애플리케이션 로그 포맷 예제
python-json-logger를 사용한 JSON 로깅 설정
"""

# 1. 의존성 설치
# pip install python-json-logger

import logging
import sys
import traceback
from pythonjsonlogger import jsonlogger
from datetime import datetime
from functools import wraps

# 2. JSON Logger 설정
class CustomJsonFormatter(jsonlogger.JsonFormatter):
    """커스텀 JSON 포맷터 - 추가 필드 자동 삽입"""

    def add_fields(self, log_record, record, message_dict):
        super(CustomJsonFormatter, self).add_fields(log_record, record, message_dict)

        # 타임스탬프 ISO 8601 형식으로 추가
        log_record['timestamp'] = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S.%fZ')

        # 로그 레벨
        log_record['level'] = record.levelname

        # 애플리케이션 메타데이터 (환경변수에서 가져오는 것을 권장)
        log_record['app'] = 'myapp'
        log_record['service-team'] = 'myteam'
        log_record['environment'] = 'production'

        # 소스 파일 정보
        log_record['logger'] = record.name
        log_record['module'] = record.module
        log_record['function'] = record.funcName
        log_record['line'] = record.lineno

# Logger 초기화
def setup_logger(name: str, level=logging.INFO):
    """JSON 로거 설정"""
    logger = logging.getLogger(name)
    logger.setLevel(level)

    # Console Handler
    handler = logging.StreamHandler(sys.stdout)
    handler.setLevel(level)

    # JSON 포맷터 적용
    formatter = CustomJsonFormatter(
        '%(timestamp)s %(level)s %(name)s %(message)s'
    )
    handler.setFormatter(formatter)

    logger.addHandler(handler)

    # 중복 로그 방지
    logger.propagate = False

    return logger

# 3. 사용 예제
logger = setup_logger(__name__, level=logging.DEBUG)

class UserService:
    """사용자 서비스 예제"""

    def __init__(self):
        self.logger = setup_logger(self.__class__.__name__)

    def process_user(self, user_id: str):
        """사용자 처리 메인 로직"""
        # 구조화된 로그 (extra 파라미터 사용)
        self.logger.info(
            "Starting user processing",
            extra={
                'userId': user_id,
                'operation': 'process_user'
            }
        )

        try:
            # 비즈니스 로직
            user = self._fetch_user(user_id)

            # 추가 컨텍스트와 함께 로그
            self.logger.info(
                "User fetched successfully",
                extra={
                    'userId': user_id,
                    'username': user['username'],
                    'email': user['email']
                }
            )

            self._validate_user(user)

            self.logger.info(
                "User processing completed",
                extra={'userId': user_id}
            )

        except UserNotFoundException as e:
            # Exception 정보와 함께 에러 로그
            self.logger.error(
                "User not found",
                extra={
                    'userId': user_id,
                    'error': str(e)
                },
                exc_info=True  # stacktrace 포함
            )
        except ValidationException as e:
            self.logger.warning(
                f"User validation failed: {str(e)}",
                extra={'userId': user_id},
                exc_info=True
            )
        except Exception as e:
            self.logger.error(
                "Unexpected error during user processing",
                extra={
                    'userId': user_id,
                    'error_type': type(e).__name__
                },
                exc_info=True
            )
            raise RuntimeError("Failed to process user") from e

    def demonstrate_log_levels(self):
        """로그 레벨별 사용 예제"""

        # DEBUG: 상세한 디버깅 정보 (개발 환경에서만)
        self.logger.debug(
            "Cache hit",
            extra={'cache_key': 'user:123'}
        )

        # INFO: 일반적인 정보성 메시지
        self.logger.info(
            "User login successful",
            extra={
                'userId': 'user123',
                'ip_address': '192.168.1.100'
            }
        )

        # WARNING: 경고 (잠재적 문제)
        self.logger.warning(
            "API rate limit approaching",
            extra={
                'current_requests': 95,
                'limit': 100
            }
        )

        # ERROR: 에러 (기능 실패)
        self.logger.error(
            "Failed to send email notification",
            extra={
                'userId': 'user123',
                'notification_type': 'password_reset'
            }
        )

        # AUDIT: 감사 로그
        self.logger.info(
            "User password changed",
            extra={
                'log_type': 'audit',
                'userId': 'user123',
                'ip_address': '192.168.1.100',
                'action': 'password_change'
            }
        )

    def log_with_masking(self, credit_card: str, password: str):
        """민감정보 마스킹 예제"""

        # ❌ 잘못된 예: 민감정보를 그대로 로깅
        # self.logger.info("Payment processed", extra={'card': credit_card})

        # ✅ 올바른 예: 민감정보 마스킹
        masked_card = self._mask_credit_card(credit_card)
        self.logger.info(
            "Payment processed",
            extra={'card': masked_card}
        )

        # ❌ 비밀번호는 절대 로깅하지 않음
        # self.logger.debug("User login", extra={'password': password})

        # ✅ 비밀번호는 로깅하지 않고 제공 여부만 기록
        self.logger.info(
            "User login attempt",
            extra={'password_provided': password is not None}
        )

    def _fetch_user(self, user_id: str) -> dict:
        """사용자 조회"""
        try:
            return self._call_external_api(user_id)
        except ApiException as e:
            raise UserNotFoundException(f"Failed to fetch user: {user_id}") from e

    def _call_external_api(self, user_id: str) -> dict:
        """외부 API 호출 시뮬레이션"""
        # 실제로는 API 호출
        if user_id == "user999":
            raise ApiException("API timeout")
        return {
            'username': 'john.doe',
            'email': 'john@example.com'
        }

    def _validate_user(self, user: dict):
        """사용자 검증"""
        if not user.get('email'):
            raise ValidationException("Email is required")

    @staticmethod
    def _mask_credit_card(card: str) -> str:
        """신용카드 번호 마스킹"""
        if not card or len(card) < 4:
            return "****"
        return f"****-****-****-{card[-4:]}"


# 4. 데코레이터를 활용한 로깅
def log_execution(logger):
    """함수 실행을 자동으로 로깅하는 데코레이터"""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            func_name = func.__name__
            logger.debug(
                f"Executing {func_name}",
                extra={
                    'function': func_name,
                    'args': str(args)[:100],  # 긴 인자는 잘라냄
                    'kwargs': str(kwargs)[:100]
                }
            )

            try:
                result = func(*args, **kwargs)
                logger.debug(
                    f"{func_name} completed successfully",
                    extra={'function': func_name}
                )
                return result
            except Exception as e:
                logger.error(
                    f"{func_name} failed",
                    extra={
                        'function': func_name,
                        'error': str(e)
                    },
                    exc_info=True
                )
                raise

        return wrapper
    return decorator


# 5. 커스텀 Exception 클래스
class UserNotFoundException(Exception):
    """사용자를 찾을 수 없음"""
    pass

class ValidationException(Exception):
    """검증 실패"""
    pass

class ApiException(Exception):
    """API 호출 실패"""
    pass


# 6. 사용 예제
if __name__ == "__main__":
    service = UserService()

    # 정상 케이스
    service.process_user("user123")

    # 에러 케이스
    try:
        service.process_user("user999")
    except Exception:
        pass

    # 로그 레벨 데모
    service.demonstrate_log_levels()


# 출력 예제 (JSON 형식)
"""
{
  "timestamp": "2025-01-15T08:30:45.123456Z",
  "level": "INFO",
  "name": "UserService",
  "message": "User fetched successfully",
  "app": "myapp",
  "service-team": "myteam",
  "environment": "production",
  "logger": "UserService",
  "module": "log-format-python",
  "function": "process_user",
  "line": 45,
  "userId": "user123",
  "username": "john.doe",
  "email": "john@example.com"
}

{
  "timestamp": "2025-01-15T08:30:46.789012Z",
  "level": "ERROR",
  "name": "UserService",
  "message": "User not found",
  "app": "myapp",
  "service-team": "myteam",
  "environment": "production",
  "logger": "UserService",
  "module": "log-format-python",
  "function": "process_user",
  "line": 67,
  "userId": "user999",
  "error": "Failed to fetch user: user999",
  "exc_info": "Traceback (most recent call last):\n  File \"log-format-python.py\", line 45, in process_user\n    user = self._fetch_user(user_id)\n  File \"log-format-python.py\", line 145, in _fetch_user\n    return self._call_external_api(user_id)\n  File \"log-format-python.py\", line 152, in _call_external_api\n    raise ApiException(\"API timeout\")\nApiException: API timeout\n\nThe above exception was the direct cause of the following exception:\n\nTraceback (most recent call last):\n  File \"log-format-python.py\", line 45, in process_user\n    user = self._fetch_user(user_id)\n  File \"log-format-python.py\", line 148, in _fetch_user\n    raise UserNotFoundException(f\"Failed to fetch user: {user_id}\") from e\nUserNotFoundException: Failed to fetch user: user999"
}
"""
