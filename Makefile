.PHONY: tflint
tflint:
	tflint --init \
	&& tflint --config ./.tflint.hcl --no-color -f compact

.PHONY: tfplan
tfplan:
	terraform plan -out=tfplan

.PHONY: tfapply
tfapply:
	terraform apply tfplan

.PHONY: tftest-integration
tftest-integration:
	terraform test -filter=integration.tftest.hcl -verbose

.PHONY: tftest-integration-fail
tftest-integration-fail:
	terraform test -filter=integration-fail.tftest.hcl -verbose

.PHONY: tftest-clean
tftest-clean:
	az group delete -n rg-apc-tf-meetup-test
