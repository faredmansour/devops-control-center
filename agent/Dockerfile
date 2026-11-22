FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    DCC_AGENT_MODE=runtime_health

WORKDIR /opt/dcc-agent

COPY agent/requirements.txt ./requirements.txt
RUN python -m pip install --no-cache-dir --upgrade pip \
    && python -m pip install --no-cache-dir -r requirements.txt

COPY agent/dcc_agent ./dcc_agent

RUN groupadd --gid 10001 dcc-agent \
    && useradd --uid 10001 --gid 10001 --create-home \
       --home-dir /home/dcc-agent --shell /usr/sbin/nologin dcc-agent

USER 10001:10001

ENTRYPOINT ["python", "-m", "dcc_agent.cli"]
