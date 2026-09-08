from crewai import Agent, Crew, Process, Task, LLM
from crewai.project import CrewBase, agent, crew, task

local_llm = LLM(
    model="openai/gpt-4o-mini",
    base_url="http://127.0.0.1:8080/v1",
    api_key="local",
)


@CrewBase
class AztecFlutterCrew():
    """AztecApp Flutter Dev Crew."""

    agents_config = "config/agents.yaml"
    tasks_config = "config/tasks.yaml"

    @agent
    def flutter_model_engineer(self) -> Agent:
        return Agent(
            config=self.agents_config["flutter_model_engineer"],
            llm=local_llm,
            verbose=True
        )

    @agent
    def flutter_service_developer(self) -> Agent:
        return Agent(
            config=self.agents_config["flutter_service_developer"],
            llm=local_llm,
            verbose=True
        )

    @agent
    def flutter_ui_developer(self) -> Agent:
        return Agent(
            config=self.agents_config["flutter_ui_developer"],
            llm=local_llm,
            verbose=True
        )

    @crew
    def crew(self) -> Crew:
        return Crew(
            agents=self.agents,
            tasks=self.tasks,
            process=Process.sequential,
            verbose=True,
        )
