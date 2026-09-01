import sys
import json
import subprocess
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent))
from aws_staging_controller import (
    AwsController,
    ControllerConfig,
    format_dns_instructions,
    is_lock_error,
    redact_output,
)


class ControllerHelpersTest(unittest.TestCase):
    def make_config(self):
        return ControllerConfig(
            aws_region="ap-southeast-1",
            aws_profile="default",
            aws_executable=Path("aws.exe"),
            terraform_executable=Path("terraform.exe"),
            terraform_directory=Path("infra/aws/envs/staging"),
            ami_id="ami-test",
            api_domain_name="api.example.com",
            api_certificate_validation_record_fqdns=["_validation.api.example.com"],
            api_health_url="https://api.example.com/health",
            admin_url="https://admin.example.com",
        )

    def test_detects_terraform_lock(self):
        self.assertTrue(is_lock_error("Error acquiring the state lock"))
        self.assertFalse(is_lock_error("Apply complete!"))

    def test_redacts_common_secret_values(self):
        text = "JWT_SECRET=very-secret MONGO_URI=mongodb+srv://user:pass@example.test/db"
        redacted = redact_output(text)
        self.assertNotIn("very-secret", redacted)
        self.assertNotIn("mongodb+srv://user:pass", redacted)

    def test_formats_copyable_dns_instructions(self):
        result = format_dns_instructions(
            "example.cloudfront.net",
            [{"name": "_validation.api.example.com", "value": "_target.acm-validations.aws"}],
        )
        self.assertIn("api CNAME -> example.cloudfront.net", result)
        self.assertIn("ACM CNAME: _validation.api.example.com", result)

    def test_start_reports_terraform_failure(self):
        messages = []
        controller = AwsController(self.make_config(), messages.append)
        controller.verify_identity = lambda: True
        controller.check_lock = lambda: True
        controller.certificate_info = lambda: (True, ["_validation.api.example.com"], [])
        controller.terraform = lambda args, show_output=True: subprocess.CompletedProcess(
            args, 1, "", "Error: CNAMEAlreadyExists"
        )
        controller.status = lambda: None

        result = controller.start()

        self.assertFalse(result.success)
        self.assertIn("still assigned elsewhere", result.message)

    def test_pending_certificate_does_not_enable_custom_alias(self):
        controller = AwsController(self.make_config(), lambda _message: None)
        tfvars = controller.make_tfvars([])
        try:
            values = json.loads(tfvars.read_text(encoding="utf-8"))
        finally:
            tfvars.unlink(missing_ok=True)
        self.assertNotIn("api_certificate_validation_record_fqdns", values)

    def test_apply_config_waits_for_issued_certificate(self):
        messages = []
        controller = AwsController(self.make_config(), messages.append)
        controller.verify_identity = lambda: True
        controller.check_lock = lambda: True
        controller.certificate_info = lambda: (
            False,
            ["_validation.api.example.com"],
            [{"name": "_validation.api.example.com", "value": "_target.acm-validations.aws"}],
        )
        controller.status = lambda: None
        controller.terraform = lambda *_args, **_kwargs: self.fail("Terraform must not apply before ACM is issued")

        result = controller.apply_config()

        self.assertFalse(result.success)
        self.assertIn("not issued", result.message)
        self.assertTrue(any("ACM CNAME" in message for message in messages))

    @patch("aws_staging_controller.urllib.request.urlopen", side_effect=urllib.error.URLError("offline"))
    def test_status_errors_are_not_reported_as_missing_resources(self, _urlopen):
        snapshots = []
        controller = AwsController(self.make_config(), lambda _message: None, lambda *args: snapshots.append(args))
        controller.terraform = lambda args, show_output=True: subprocess.CompletedProcess(args, 1, "", "unavailable")
        controller.aws = lambda args, show_output=True: subprocess.CompletedProcess(args, 1, "", "unavailable")
        controller.certificate_info = lambda: (False, [], [])

        result = controller.status()

        self.assertFalse(result.success)
        self.assertEqual(snapshots[-1][-4], False)
        self.assertIn("unknown", snapshots[-1][0])

    @patch("aws_staging_controller.urllib.request.urlopen", side_effect=urllib.error.URLError("offline"))
    def test_terraform_only_resources_keep_destroy_available(self, _urlopen):
        snapshots = []
        controller = AwsController(self.make_config(), lambda _message: None, lambda *args: snapshots.append(args))

        def terraform(args, show_output=True):
            if args[:2] == ["state", "list"]:
                return subprocess.CompletedProcess(args, 0, "aws_nat_gateway.this\naws_elasticache_replication_group.cache\n", "")
            return subprocess.CompletedProcess(args, 1, "", "no outputs")

        controller.terraform = terraform
        controller.aws = lambda args, show_output=True: subprocess.CompletedProcess(args, 0, "[]", "")
        controller.certificate_info = lambda: (False, [], [])

        result = controller.status()

        self.assertTrue(result.success)
        self.assertEqual(snapshots[-1][1], True)
        self.assertEqual(snapshots[-1][-1], False)


if __name__ == "__main__":
    unittest.main()
