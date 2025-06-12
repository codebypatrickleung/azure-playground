"""Flask web application integrating Azure OpenAI with Microsoft Entra authentication."""

import os
from flask import Flask, render_template, request
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from openai import AzureOpenAI

app = Flask(__name__)

# Initialize the Azure OpenAI client with Microsoft Entra authentication
token_provider = get_bearer_token_provider(
    DefaultAzureCredential(), "https://cognitiveservices.azure.com/.default"
)
client = AzureOpenAI(
    api_version="2024-12-01-preview",
    azure_endpoint=os.getenv("AZURE_OPENAI_ENDPOINT"),
    azure_ad_token_provider=token_provider,
)

@app.route('/', methods=['GET', 'POST'])
def index():
    """Render the main page and handle user message submission to Azure OpenAI."""
    response = None
    if request.method == 'POST':  #  Handle form submission
        user_message = request.form.get('message')
        if user_message:
            try:
                # Call the Azure OpenAI API with the user's message
                completion = client.chat.completions.create(
                    model="gpt-4.1",
                    messages=[{"role": "user", "content": user_message}]
                )
                ai_message = completion.choices[0].message.content
                response = ai_message
            except Exception as e:
                response = f"Error: {e}"
    return render_template('index.html', response=response)


if __name__ == '__main__':
    app.run(host="0.0.0.0", port=5001)