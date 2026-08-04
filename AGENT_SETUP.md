# env0 Self-Hosted Agent — Setup Runbook

This runbook walks a human operator through bootstrapping the env0 self-hosted agent on
the `dvtl815-poc` EKS cluster (region `us-west-2`, account `355433853014`) and wiring it
to the `dvtl-815-resources` project in the env0 UI.

---

## 1. Prerequisites

**EKS Pod Identity Agent addon.**
The EKS Pod Identity Agent addon is already confirmed installed and in ACTIVE status on
`dvtl815-poc`. No action is required here, but this addon is what allows the
`env0-deploy` ServiceAccount to receive AWS credentials automatically — without it, the
deploy job will have no IAM identity and every `aws` call will fail.

**VPN access and an admin kubeconfig.**
The `dvtl815-poc` API server endpoint is private (not reachable from the public internet).
You must be connected to the corporate VPN, and you must have a kubeconfig that gives you
admin access to the cluster before running any `kubectl`, `helm`, or `tofu` commands in
this runbook.

---

## 2. Apply the `agent/` Terraform Stack First

Before installing the Helm chart, apply the `agent/` stack by hand:

```bash
cd agent
tofu init
tofu apply
```

**Why this must happen first — the bootstrap-ordering requirement.**

The Helm chart installs the env0 agent process, but the agent process itself needs a
Kubernetes identity and AWS permissions before it can run any deployment job. The `agent/`
Terraform stack is what creates all of those prerequisites:

- The **IAM role** that will be assumed by deployment-job pods.
- The **EKS Pod Identity association** that binds that IAM role to the `env0-deploy`
  ServiceAccount in the `env0-agent` namespace.
- The **`env0-deploy` ServiceAccount** itself in the `env0-agent` namespace.
- The **cluster-admin ClusterRoleBinding** that gives that ServiceAccount full Kubernetes
  RBAC permissions so deployment jobs can create namespaces, apply manifests, and so on.

If you skip this step and install the Helm chart first, the deployment-job pod will start
but immediately fail: it has no AWS credentials (Pod Identity association does not exist
yet) and no Kubernetes RBAC (ClusterRoleBinding does not exist yet). You will see
`Unauthorized` errors from both the AWS and Kubernetes clients. Always apply `agent/`
first. Its state is stored at key `agent/terraform.tfstate` in the backend.

---

## 3. env0 UI Steps — Create the Agent Token

1. Log in to the env0 UI and go to **Organization Settings > Agents**.
2. Click **Manage Secrets**, then **Create Secret** to generate a new agent pool and its
   access token.
3. The UI will show the `agentAccessToken` exactly once. **Copy it immediately** and keep
   it somewhere safe (a password manager or secrets store). You cannot retrieve it again.
4. On the same Agents page, find the **`dvtl-815-resources`** project in the project list
   and use the dropdown to assign it to the newly created agent pool.

**Security warning:** The `agentAccessToken` is a secret credential. Never commit it to
the repository, never paste it into any file tracked by git, and never share it in a chat
channel or ticket.

---

## 4. Install the Agent with Helm

Add the env0 Helm repository:

```bash
helm repo add env0 https://env0.github.io/self-hosted
```

Then install the agent into the `env0-agent` namespace:

```bash
helm install --create-namespace env0-agent env0/env0-agent \
  --namespace env0-agent \
  --set-string agentAccessToken='<token-from-UI>' \
  --set-string deploymentJobServiceAccountName='env0-deploy' \
  -f values.customer.yaml
```

Replace `<token-from-UI>` with the token you copied in step 3.

**Critical:** The value passed to `--set-string deploymentJobServiceAccountName` must be
exactly `env0-deploy` — byte for byte. This tells the agent which ServiceAccount to
attach to each deployment-job pod. If this value does not match the ServiceAccount that
the `agent/` Terraform stack created, the pod will start with the wrong identity (or no
identity at all) and every deployment will fail with `Unauthorized`. The same name appears
in `values.customer.yaml` under `deploymentJobServiceAccountName` and is included via
`-f values.customer.yaml`; the `--set-string` flag on the command line overrides or
confirms that same key and must match.

---

## 5. Flip the Code and Trigger a Deploy

Once the agent pod is running (see Verification below), you can start using it:

1. Merge the `providers.tf` in-cluster-auth change on the `dvtl-815-resources` repo. This
   is the change that switches the Kubernetes/Helm providers from static kubeconfig
   credentials to in-cluster authentication, so the deploy job no longer needs a kubeconfig
   file passed in from outside.
2. In the env0 UI, open the **`dvtl-815-resources`** project and trigger a new deployment,
   making sure the target agent pool is the self-hosted pool you created in step 3.

---

## 6. Verification

After installation, use the checks below to confirm the system is healthy and to diagnose
any failures quickly.

### Understanding the two failure classes

Before looking at specific `kubectl` output, learn to distinguish between the two root
causes you are most likely to encounter:

- **`i/o timeout` (to `10.194.72.167:443`)** — This is a **network problem**. The agent
  pod is running inside the cluster but cannot reach the Kubernetes API server on port 443.
  The cluster's security group may not have an ingress rule allowing port 443 from the
  agent pod's subnet. This is an SRE/infrastructure ask: the eks-factory team owns the
  cluster security groups and must add the rule. You cannot fix this yourself by adjusting
  Terraform in this repo.

- **`Unauthorized` or `forbidden`** — This is an **RBAC or identity problem**. Either the
  Pod Identity association is missing or misconfigured, the `env0-deploy` ServiceAccount
  does not exist, or the ClusterRoleBinding was not applied. Re-check that the `agent/`
  stack was applied successfully and that the ServiceAccount name is `env0-deploy`
  everywhere.

### Concrete checks

**1. Confirm the agent pod is Running:**

```bash
kubectl -n env0-agent get pods
```

You should see at least one pod in `Running` status. If the pod is in `CrashLoopBackOff`
or `Error`, check its logs with `kubectl -n env0-agent logs <pod-name>`.

**2. Confirm Pod Identity is delivering AWS credentials:**

Run a one-off pod as the `env0-deploy` ServiceAccount and call `aws sts get-caller-identity`:

```bash
kubectl run --rm -it --restart=Never aws-id-check \
  --image=amazon/aws-cli \
  --serviceaccount=env0-deploy \
  --namespace=env0-agent \
  -- sts get-caller-identity
```

The response should show the IAM role ARN that the `agent/` stack created for
`env0-deploy`. If it returns the node's instance role or an error, the Pod Identity
association is not wired correctly.

**3. Confirm the ClusterRoleBinding gives Kubernetes admin rights:**

```bash
kubectl auth can-i create namespaces \
  --as=system:serviceaccount:env0-agent:env0-deploy
```

The answer should be `yes`. If it is `no`, the ClusterRoleBinding from the `agent/` stack
is missing or scoped to the wrong namespace.

**4. Confirm the internal ALB is reachable from VPN/in-VPC:**

```bash
curl https://env0-dvtl815.355433853014.natera.io
```

Run this from a machine that is on the VPN or inside the VPC. A successful HTTP response
(even a 200 or a redirect) confirms that the internal Application Load Balancer is
serving traffic correctly. A connection timeout from this URL means the caller is not
on the VPN or the ALB security group is blocking the request — it does not indicate a
problem with the agent itself.
