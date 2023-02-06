import pytest

from src.api import API


@pytest.fixture
def api():
    return API()
