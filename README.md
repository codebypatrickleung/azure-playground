# Azure Playground

This repository serves as my own sandbox for exploring and testing Azure services. It is intended for experimenting with new features, learning about Azure, and building applications that leverage Azure resources. Written in Terraform, so that I can easily tear down the infrastructure when I'm done testing.

## Azure Infrastructure

The Terraform code in this repository provisions the following Azure services:

- Azure OpenAI Services
- Azure Kubernetes Service (AKS)
- Azure Container Registry (ACR)

I use mostly Azure Verified Modules to take out all the heavy lifting. If you want to learn more about the modules I used, you can find them in the [Terraform](https://registry.terraform.io/search/modules?namespace=Azure&provider=azure&q=Azure%2Favm) registry. 

## Application

The current application is a simple Flask-based Python app deployed on the AKS cluster and is intend to provide a solid foundation for developing large language model (LLM) applications on Azure. It serves as a starting point for building more advanced solutions. The LLM model utilizes the [model router](https://learn.microsoft.com/en-us/azure/ai-services/openai/concepts/model-router) (introduced May 2025), enabling the app to route requests to different models based on the request type. This seems interesting as we might be able to combine different models for different tasks.

## Getting Started

1. Clone the repository.

2. Deploy the infrastructure using Terraform:

    ```bash
    cd infrastructure
    terraform init
    terraform apply -auto-approve

3. Deploy the application:

    Note that the application deployment script is written for MacOS. If you are using a different operating system, you may need to adjust the script accordingly.

    ```bash
    cd ..
    ./script/deploy.sh
    ```
4. Access the application:

    Open your web browser and navigate to the URL of the AKS cluster. The external IP address of the AKS service is shown in the output of the deployment script. You can also find the URL in the Azure portal under the AKS service. The port is set to 5001 by default, so the URL will look like `http://<external-ip>:5001`. Have fun exploring the application!

## Cleanup

To tear down the infrastructure and remove all resources created by Terraform, run the following command in the `infrastructure` directory:

```bash
terraform destroy -auto-approve
```

## License
This repository is licensed under the MIT License. See the [LICENSE](LICENSE) file for more details.