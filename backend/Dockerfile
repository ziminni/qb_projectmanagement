# backend/Dockerfile — BuildPro CPMS (Repo #2)
FROM python:3.12-slim

# Prevent Python from writing .pyc files and buffering stdout
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Set the working directory inside the container
WORKDIR /app

# Install system dependencies (psycopg2 needs gcc + libpq-dev to build)
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc libpq-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies (separate layer for build caching)
COPY requirements.txt /app/
RUN pip install --upgrade pip \
    && pip install -r requirements.txt

# Copy the Django project code
COPY . /app/

EXPOSE 8001

# Default dev command; docker-compose overrides with migrate + runserver.
CMD ["python", "manage.py", "runserver", "0.0.0.0:8001"]