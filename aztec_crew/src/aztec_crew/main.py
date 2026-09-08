import sys
from pathlib import Path
from aztec_crew.crew import AztecFlutterCrew

FEATURE = "feature0"


def run():
    Path(f"output/{FEATURE}").mkdir(parents=True, exist_ok=True)

    print("\n" + "=" * 60)
    print(f"🚀 AztecApp Flutter Crew — {FEATURE}")
    print("🤖 Modelo: Qwen2.5-Coder 3B local via llama.cpp")
    print("=" * 60 + "\n")

    try:
        result = AztecFlutterCrew().crew().kickoff()
        print(f"\n✅ Completado. Revisa output/{FEATURE}/")
        return result
    except Exception as e:
        print(f"\n❌ Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    run()
