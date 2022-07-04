FROM python:3.8-buster as builder

ENV PYTHONUNBUFFERED=1

RUN mkdir -p /app
WORKDIR /app

COPY poetry.lock pyproject.toml ./

RUN pip install -U pip poetry

RUN poetry config virtualenvs.in-project true && \ 
    poetry install --no-dev

FROM python:3.8-slim-buster as production

ENV PYTHONUNBUFFERED=1

COPY --from=builder /app/.venv /app/.venv
ENV PATH=/app/.venv/bin:$PATH
COPY ./app.py /app/app.py

WORKDIR /app

# EXPOSE 80

CMD ["uvicorn", "app:app", "--reload", "--host", "0.0.0.0", "--port", "80"]
