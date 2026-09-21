resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"   #who issues tokens

  client_id_list = ["sts.amazonaws.com"]                #aud = audience. Who the token is meant for.

  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]    #fingerprint of the issuer's TLS certificate
}

resource "aws_iam_role_policy" "github_actions_policy" {
  name = "${var.project_name}-github-actions-ecr"
  role = aws_iam_role.github_actions.id

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:CompleteLayerUpload",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart"

        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Sid    = ""
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
        Condition = {
            StringEquals = {"token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"}
            StringLike = {"token.actions.githubusercontent.com:sub" = "repo:FaboCloudsurf@140220685/Tech_challenge_2@1357809367:*"}
        }
      },
    ]
  })
}


