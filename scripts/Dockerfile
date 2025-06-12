FROM python:3.13.4-slim

# Set the working directory in the container
WORKDIR /app

# Copy the everything under the app directory contents into the container at /app
COPY app/ /app/

# Upgrade pip to the latest version
RUN pip install --upgrade pip

# Install the required dependencies
RUN pip install --no-cache-dir -r ../app/requirements.txt

# Make port 5001 available to the world outside this container
EXPOSE 5001

# Define environment variable
ENV AZURE_OPENAI_ENDPOINT="<TODO>"

# Run app.py when the container launches
CMD ["python", "../app/app.py"]

