#!/usr/bin/env python3
"""Cross-process MCP regression test. Build the Release app in .build before running."""
import concurrent.futures
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest
import uuid


def sample_material(schema):
    exercises = {}
    for key in schema["exercises"]["properties"]:
        item = dict(id=key, kind="gap", prompt="I ___ ready.", explanation="С I используем am.",
                    topic="Грамматика", acceptedAnswers=["am"])
        if key.endswith("-listening"):
            item.update(kind="choice", prompt="Что ты услышал?", speechText="Tea, please.",
                        options=["Чай", "Кофе"], acceptedAnswers=["Чай"])
        elif key.endswith("-applied"):
            item = dict(id=key, kind="dialogue", prompt="Закажи чай.", rubric="Вежливая просьба на английском.",
                        topic="Письмо")
        exercises[key] = item
    cards = [dict(id=f"word-{index}", english=f"word {index}", russian=f"слово {index}",
                  example="I know this word.", exampleTranslation="Я знаю это слово.")
             for index in range(schema["vocabulary"]["minItems"])]
    return dict(goal="Заказать чай", title="Заказываем чай", theory="Используй please.", exercises=exercises,
                vocabulary=cards)


def fake_codex():
    def emit(message):
        print(json.dumps(message), flush=True)

    for line in sys.stdin:
        request = json.loads(line)
        method = request["method"]
        params = request["params"]
        if method == "initialized":
            continue
        if method == "initialize":
            result = {}
        elif method == "model/list":
            result = {"data": [dict(model="test-tutor", displayName="Tutor", isDefault=False,
                                    defaultReasoningEffort="low", supportedReasoningEfforts=[
                                        {"reasoningEffort": "low"}, {"reasoningEffort": "medium"}])]}
        elif method == "thread/start":
            assert params["model"] == "test-tutor"
            result = {"thread": {"id": "thread"}}
        elif method == "turn/start":
            assert params["effort"] == "medium"
            assert "Sample plan for 2 lessons." in params["input"][0]["text"]
            content = sample_material(params["outputSchema"]["properties"])
            prompt = params["input"][0]["text"]
            if "Produce only step 1 of" in prompt:
                card = content["exercises"]["q02-typing"]
                card.update(kind="translationCard", prompt="после школы", acceptedAnswers=["after school"])
                if "Revise the previous material" not in prompt:
                    card["prompt"] = "Транскрипт: We meet after school. Переведи фразу «после школы»."
            emit({"id": request["id"], "result": {"turn": {"id": "turn"}}})
            emit({"method": "item/completed", "params": {"threadId": "thread", "turnId": "turn",
                  "item": {"type": "agentMessage", "text": json.dumps(content)}}})
            emit({"method": "turn/completed", "params": {"threadId": "thread",
                  "turn": {"id": "turn", "status": "completed"}}})
            continue
        else:
            raise ValueError(method)
        emit({"id": request["id"], "result": result})


class AgentGenerationTest(unittest.TestCase):
    def test_shared_settings_and_idempotent_generation(self):
        root = Path(__file__).resolve().parents[1]
        binary = root / ".build/Build/Products/Release/English Practice.app/Contents/MacOS/English Practice"
        with tempfile.TemporaryDirectory() as directory:
            cli = Path(directory, "codex")
            shutil.copyfile(__file__, cli)
            cli.chmod(0o755)
            env = dict(os.environ, ENGLISH_DATA_DIR=directory)

            def call(name, args):
                request = dict(jsonrpc="2.0", id=1, method="tools/call", params=dict(name=name, arguments=args))
                process = subprocess.run([binary, "--mcp", "-codexPath", cli], input=json.dumps(request) + "\n",
                                         env=env, capture_output=True, text=True, check=True, timeout=15)
                result = json.loads(process.stdout)["result"]
                self.assertFalse(result["isError"], result)
                return json.loads(result["content"][0]["text"])

            initial = call("list_course", {})
            request = dict(requestId=str(uuid.uuid4()), topic="В кафе", goal="Заказать чай",
                           moduleId=initial[0]["moduleId"], sectionId=initial[0]["sectionId"])
            settings = dict(model="test-tutor", effort="medium", lessonsPerSection=2, exercisesPerLesson=21,
                            reviewExercises=7, cardsPerSection=9, testExercises=22, passingPercent=80,
                            prompts={"section": "Sample plan for {{lessonsPerSection}} lessons."})
            with sqlite3.connect(Path(directory, "course.sqlite3")) as db:
                db.execute("INSERT INTO agent_settings VALUES (1, ?)", (json.dumps(settings),))
                old = json.dumps(dict(draft={"one": "Hi"}, attempts=[dict(id=str(uuid.uuid4()), date=100,
                                      answers={"one": "Hello"}, feedback=[])], isRetrying=True))
                db.execute("INSERT INTO progress VALUES (?, ?)", (initial[0]["lessonId"], old))
                db.commit()
                with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
                    starts = list(pool.map(lambda _: call("generate_section", request), range(3)))
                self.assertEqual(len({job["requestId"] for job in starts}), 1)
                # A settings change after launch must not affect subsequent steps in this job.
                db.execute("DELETE FROM agent_settings")
                db.commit()
                for _ in range(100):
                    job = call("get_generation_status", {"requestId": request["requestId"]})
                    if job["status"] != "running":
                        break
                    time.sleep(0.1)
                self.assertEqual(job["status"], "completed", job)
                self.assertEqual((job["model"], job["effort"]), ("test-tutor", "medium"))
                self.assertEqual(call("generate_section", request)["lessonIds"], job["lessonIds"])
                self.assertEqual(len(call("list_course", {})), len(initial) + 4)
                lessons = [json.loads(db.execute("SELECT data FROM lessons WHERE id=?", (key,)).fetchone()[0])
                           for key in job["lessonIds"]]
                self.assertEqual([len(lesson["exercises"]) for lesson in lessons], [21, 21, 21, 7])
                repaired = next(item for item in lessons[0]["exercises"] if item.get("storedFormat") == "translationCard")
                self.assertEqual(repaired["prompt"], "после школы")
                self.assertEqual(repaired["acceptedAnswers"], ["after school"])
                self.assertEqual(lessons[2]["kind"], "homework")
                self.assertTrue(lessons[3]["spacedReview"])
                self.assertEqual(db.execute("SELECT count(*) FROM agent_requests").fetchone()[0], 5)
                self.assertEqual(db.execute("SELECT data FROM progress").fetchone()[0], old)


if __name__ == "__main__":
    if sys.argv[1:2] == ["app-server"]:
        fake_codex()
    else:
        unittest.main()
