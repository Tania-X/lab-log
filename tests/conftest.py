import pytest
from unittest.mock import MagicMock

@pytest.fixture(scope="session")
def mock_db():
    """全局模拟SeekDBClient，用于所有需要数据库的测试"""
    mock_client = MagicMock()
    # 设置一些默认返回值
    mock_client.insert_event_log.return_value = None
    mock_client.insert_emergency_log.return_value = None
    mock_client.get_pending_emergency_count.return_value = 0
    mock_client.get_emergencies.return_value = []
    mock_client.resolve_emergency.return_value = True
    mock_client.get_user_by_username.return_value = None
    mock_client.insert_user.return_value = True
    mock_client.get_table_list.return_value = ["users", "event_logs", "emergencies"]
    mock_client.query_table.return_value = ([], 0)
    mock_client.vector_search.return_value = []
    return mock_client

@pytest.fixture(scope="session")
def mock_encryption_service():
    """全局模拟加密服务"""
    mock_service = MagicMock()
    mock_service.encrypt_field.return_value = "encrypted_data"
    return mock_service

@pytest.fixture(scope="function")
def temp_dir(tmp_path):
    """临时目录，用于文件操作测试"""
    return tmp_path

@pytest.fixture(scope="session")
def test_config():
    """测试配置"""
    return {
        "database_url": "sqlite:///:memory:",
        "secret_key": "test_secret_key_for_testing",
        "api_key": "test_dashscope_api_key"
    }

@pytest.fixture(scope="session")
def valid_user_session():
    """有效的用户会话令牌"""
    return "valid_user_session_token_12345"

@pytest.fixture(scope="session")
def admin_user_session():
    """管理员会话令牌"""
    return "valid_admin_session_token_67890"

@pytest.fixture(scope="session")
def sample_event_log():
    """示例事件日志"""
    from storage.models import EventLog
    return EventLog(
        event_id="test_event_001",
        segment_id="test_seg_001",
        start_time="2024-01-01T10:00:00",
        end_time="2024-01-01T10:01:00",
        event_type="action",
        structured={"person_id": "p1", "equipment": ["烧杯"]},
        raw_text="用户拿起烧杯进行实验"
    )

@pytest.fixture(scope="session")
def sample_emergency():
    """示例紧急事件"""
    from storage.models import Emergency
    return Emergency(
        emergency_id="test_emerg_001",
        description="测试紧急事件：化学品泄漏",
        status="PENDING",
        start_time="2024-01-01T10:00:00",
        end_time="2024-01-01T10:01:00",
        segment_id="test_seg_001"
    )

@pytest.fixture(scope="session")
def sample_video_result():
    """示例视频理解结果"""
    from video_processing.interface import VideoUnderstandingResult, EventLog, PersonInfo
    return VideoUnderstandingResult(
        events=[
            EventLog(
                event_id="result_event_001",
                segment_id="result_seg_001",
                start_time="2024-01-01T10:00:00",
                end_time="2024-01-01T10:01:00",
                event_type="action",
                structured={"person_id": "p1", "equipment": ["试管"]},
                raw_text="用户操作试管"
            )
        ],
        persons=[
            PersonInfo(person_id="p1", appearance="身穿白大褂的研究员")
        ],
        equipment=["试管", "烧杯"],
        emergencies=[]
    )