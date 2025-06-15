FROM python:3.13.4-slim

WORKDIR /app

COPY app/ /app/

RUN apt-get update && apt-get install -y --no-install-recommends \
    azure-cli 

RUN pip install --upgrade pip

RUN pip install --no-cache-dir -r ../app/requirements.txt

EXPOSE 5001

CMD ["python", "../app/app.py"]

