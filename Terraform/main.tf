terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "us-east-1"  # Changed to North Virginia
  shared_credentials_files = ["~/.aws/credentials"]
}

resource "aws_instance" "k8s_master" {
  # Use a valid Ubuntu AMI ID for the us-east-1 region
  ami           = "ami-04f59c565deeb2199" 
  instance_type = "t2.medium"             

  key_name = "sheethalnv"         

  # Use the user_data argument to execute the shell script
  user_data = file("k8s-setup.sh")

  tags = {
    Name = "Sheethal-K8s-Master"
  }
}
