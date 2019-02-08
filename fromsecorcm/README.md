# Helm Plugin fromsecorcm

This Helm plugin pulls data from preexistent secrets or configmaps before Helm deployment. 

This way you can use replacement vars into your templates that uses values already set into the server.

Only gets values from secrets or configmaps in the deployment namespace.

## Usage

You need to create a file called fromsecorcm.yaml into your root chart dir.

    .
    ├── charts
    ├── Chart.yaml
    ├── fromsecorcm.yaml
    ├── templates
    │   ├── deployment.yaml
    │   ├── _helpers.tpl
    │   ├── ingress.yaml
    │   ├── NOTES.txt
    │   ├── service.yaml
    │   └── tests
    │       └── test-connection.yaml
    └── values.yaml

The content should be something like this:

    fromsecorcm:
      myvalue: {{ .Secret.mysecret.password }}
      myvalue2: {{ .Configmap.mycm.username }}

The first line will pull into *myvalue* the value stored in a secret called *mysecret* in a key called *password*.

The second one will pull into *myvalue2* from a configmap called *mycm* a value from key *username*.

Then you can use this values into your templates like this:

    username: {{ .Values.fromsecorcm.myvalule2 }}

Finally you need to make your call to helm through the plugin:

    helm fromsecorcm <your chain>

e.g.

    helm fromsecorcm install --name kungfu --namespace kungfu -f values.yaml .

## Use case

Why I did this plugin?

This is the scenario. You automate infra provisioning with Terraform. Then automatically you deploy an ingress-controller against an ELB (AWS) using *internal* mode.

This gives you an URL. So you can capture it and store it into a secret or configmap for later use.

Later you deploy your project,that use an ingress and needs to know the host (the url you previously deployed). So you can take it from your secret or configmap automatically when deploy with helm.

That's it.

