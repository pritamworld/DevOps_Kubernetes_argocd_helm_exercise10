# Intall terraform
https://developer.hashicorp.com/terraform/install

# Run following command for terraform
```bash
terraform init
terraform validate
terrafrom fmt
terraform plan

ssh-keygen -t rsa -b 4096 -C "azure-vm-key"
type $env:USERPROFILE\.ssh\id_rsa.pub
terraform plan
terraform apply -auto-approve

ssh azureuser@20.151.16.149
terraform destroY
```

# Run to execute shell or Powershell script
``` bash
chmod +x deploy.sh
.\deploy.ps1
terraform destroy -auto-approve
```


# SSH to vm and run below given commands
```bash
docker --version
ansible --version
kubectl version --client
helm version
cat ~/ansible-success.txt
```


# Run Scripot

```
chmod +x deploy.sh
./deploy.sh
```