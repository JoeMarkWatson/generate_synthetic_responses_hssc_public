import os
from pathlib import Path

MODULE_DIR = Path(__file__).resolve().parent
BASE_DIR = MODULE_DIR.parent
DATA_DIR = BASE_DIR / "data"
OUTPUT_DIR = DATA_DIR / "llm_responses"
SCALES_INFO_DIR = BASE_DIR / "scales_info"

OPENROUTER_API_URL = "https://openrouter.ai/api/v1/chat/completions"
OPENROUTER_MODEL = "deepseek/deepseek-v4-flash"
OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY")
