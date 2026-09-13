"""Small Windows GUI for the ParaGO AWS staging lifecycle.

This tool delegates infrastructure changes to the repository's Terraform root
and uses the user's existing AWS CLI profile. It intentionally stores no AWS
credentials. I wa I wait I think it should be that money should not go to machines bracing to skip to say first surgicals and steep as possible tell each kind of dragon only it's a debt breath first surgery exports every path one step at a time spreading out in all directions until it finds the exit depth first search can fit lucky and chooses the right route but breath first search always finds the shortest path these are two algorithms racing to skip the same maze depth first search goals as D as possible down your phone and put yourself taking a few steps backwards bring down, taking off your shoe, turning it out to the side of the straight arm and then looking up. Next put in that video in the country app select it and hit reverse to misreverse the ball clip making it look like the shoe is actually flying in scroll to right when the shoes flowing in split here then go to effects videos cancer to recolor flame select kind of just the color and intensity of that aura around your body. Finally, after strong stamp, pull down to the side, take key frames, short to capture the shoe and pull the strong sham to the frame. How hard a little bit is sorry I just got caught like survival and just run over it survival you take a wax exposed cover bulk and throw it on top of your block. Yeah, we need this to Isnah to a placks need to draw against good I need to blush purse to my blush and so there matters joking so yeah sunskrit I'm feeling like I'm sending you some sunshine here you go to in I hope you brought your sunscreen I'm feeling like a pocket you some sunshine here you go in I hope you brought your sunscreen a few some sunshine here you go I hope you brought your sunscreen I'm feeling like a puck this shootno it's not in large for one eight spools control onset about there shirts suppose if a bhaker if a publish pressure into material sint basic verification experiments time to wallon different I think just security to picture something to fucking tools if maybe s me rock members to a file on you know touch low in there one year to start to start to barris integralrooms behaves bullying is bad small jish out there can be started swinging his arm around making it look like you researching but in reality rollers have developed another achievement for full state to the fold stage early microphis bonds you in the matrix called and this block lets you really world by providing items that generate worlds like this pretty insane so play to craft as many worlds as possible and lock as many custom items and abilities they look so cool and lastly finally craft they put you all at this group like I'm the matrix a bunch of purpose shrinkers and all the worlds that generates go to run this entire way is the right way to go to first world is serving here we go and regenerate and let's enter the mines in five four we are in there where they should not be a bunch of pulsion effects on the top left and I need to unlock there's a lot of things were me to unlock like drafting I can't make craft anything you see all this white stuff all right the world looks a little funky there's some blackstone on the mountains which should not be there and a little head right here there's also a lush by a love ground over there yo all these awards are killing the fish chill right here with clay has some sort of value later's useless far results of leave as I dimension is define a glue become portal and once we leave we can never come back so it is very important for us to collect as many items as we can in this world so we can get tax to unlock some player operates start crafting also to get in green world piece of world or anything the highest value I found the exit portal this is how we leave chicken's gonna be worth something right chicken is worth value there is some core right here but I can't even mini cause I kind of craft anything as much clay as possible of servir can't relieve in the mindser acts and I have unlocked some new ingredients like a floating islands can also unlock restoration which allows me to find me for speed this is very different to speed I don't see the effect on my effort be changed after each minds like Mario of Luck pets so access my inventory ability to crafting inventory alright here insidelands pigs and yeah
"""

from __future__ import annotations

import json
import os
import queue
import re
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from tkinter import END, BOTH, DISABLED, NORMAL, Tk, StringVar, Text, messagebox
from tkinter import ttk


ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = Path(__file__).with_name("aws_staging_config.json")
LOG_PATH = Path(__file__).with_name("aws-staging-controller.log")
SECRET_PATTERNS = [
    re.compile(r"(?i)(password|secret|token|private[_ -]?key|api[_ -]?key)\s*[=:]\s*[^\s,}]+"),
    re.compile(r"(?i)(mongodb(?:\+srv)?://)[^\s]+"),
]
ANSI_PATTERN = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")


def redact_output(value: str) -> str:
    result = ANSI_PATTERN.sub("", value)
    for pattern in SECRET_PATTERNS:
        result = pattern.sub(lambda match: match.group(0).split("=", 1)[0] + "=<redacted>" if "=" in match.group(0) else "<redacted>", result)
    return result


def is_lock_error(output: str) -> bool:
    lowered = output.lower()
    return "error acquiring the state lock" in lowered or "failed to acquire lock" in lowered


def has_running_terraform() -> bool:
    result = subprocess.run(
        ["tasklist", "/FI", "IMAGENAME eq terraform.exe", "/NH"],
        capture_output=True,
        text=True,
        check=False,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )
    return "terraform.exe" in result.stdout.lower()


def format_dns_instructions(cloudfront_domain: str, validation_records: list[dict]) -> str:
    lines = []
    if cloudfront_domain:
        lines.append(f"Namecheap: api CNAME -> {cloudfront_domain}")
    for record in validation_records:
        name = str(record.get("name") or "").strip()
        value = str(record.get("value") or "").strip()
        if name and value:
            lines.append(f"ACM CNAME: {name} -> {value}")
    return " | ".join(lines) if lines else "DNS updates: unavailable until AWS staging is created."


@dataclass(frozen=True)
class OperationResult:
    success: bool
    message: str


@dataclass
class ControllerConfig:
    aws_region: str
    aws_profile: str
    aws_executable: Path
    terraform_executable: Path
    terraform_directory: Path
    ami_id: str
    api_domain_name: str
    api_certificate_validation_record_fqdns: list[str]
    api_health_url: str
    admin_url: str

    @classmethod
    def load(cls) -> "ControllerConfig":
        data = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
        return cls(
            aws_region=data["aws_region"],
            aws_profile=data.get("aws_profile", "default"),
            aws_executable=Path(data["aws_executable"]),
            terraform_executable=Path(data["terraform_executable"]),
            terraform_directory=ROOT / data["terraform_directory"],
            ami_id=data["ami_id"],
            api_domain_name=data["api_domain_name"],
            api_certificate_validation_record_fqdns=data.get("api_certificate_validation_record_fqdns", []),
            api_health_url=data["api_health_url"],
            admin_url=data["admin_url"],
        )


class AwsController:
    def __init__(self, config: ControllerConfig, emit, set_status=None):
        self.config = config
        self.emit = emit
        self.set_status = set_status or (lambda *_args: None)

    def _env(self) -> dict[str, str]:
        env = os.environ.copy()
        env["AWS_PAGER"] = ""
        return env

    def command(
        self,
        executable: Path,
        args: list[str],
        cwd: Path | None = None,
        show_output: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        command = [str(executable), *args]
        self.emit("$ " + " ".join(f'"{part}"' if " " in part else part for part in command))
        result = subprocess.run(
            command,
            cwd=str(cwd) if cwd else None,
            env=self._env(),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        combined = redact_output((result.stdout or "") + (result.stderr or ""))
        if show_output and combined.strip():
            self.emit(combined.rstrip())
        return result

    def aws(self, args: list[str], show_output: bool = True) -> subprocess.CompletedProcess[str]:
        full_args = [*args, "--region", self.config.aws_region]
        if self.config.aws_profile:
            full_args.extend(["--profile", self.config.aws_profile])
        return self.command(self.config.aws_executable, full_args, show_output=show_output)

    def terraform(self, args: list[str], show_output: bool = True) -> subprocess.CompletedProcess[str]:
        return self.command(
            self.config.terraform_executable,
            [f"-chdir={self.config.terraform_directory}", *args],
            show_output=show_output,
        )

    def verify_identity(self) -> bool:
        result = self.aws(["sts", "get-caller-identity", "--output", "json"])
        if result.returncode != 0:
            self.emit("AWS identity check failed. Sign in with the configured AWS CLI profile.")
            return False
        self.emit("AWS identity verified.")
        return True

    def driver_documents_bucket(self) -> str:
        result = self.aws(
            ["sts", "get-caller-identity", "--query", "Account", "--output", "text"],
            show_output=False,
        )
        account_id = result.stdout.strip() if result.returncode == 0 else ""
        if not account_id or account_id == "None":
            return ""
        return f"parago-driver-documents-{account_id}-{self.config.aws_region}"

    def check_driver_documents_bucket(self, *, required: bool = False) -> bool:
        bucket = self.driver_documents_bucket()
        if not bucket:
            self.emit("Driver documents: AWS account could not be determined.")
            return False
        result = self.aws(
            ["s3api", "head-bucket", "--bucket", bucket],
            show_output=False,
        )
        if result.returncode == 0:
            self.emit(f"Driver documents: persistent bucket ready ({bucket}).")
            return True
        self.emit(
            "Driver documents: persistent bucket is missing. Run Terraform apply once in "
            "infra/aws/bootstrap before starting staging."
        )
        if required:
            self.emit("Start was stopped so driver license uploads cannot be created without storage.")
        return False

    def certificate_info(self) -> tuple[bool, list[str], list[dict]]:
        result = self.command(self.config.aws_executable, [
            "acm", "list-certificates", "--region", "us-east-1", "--profile", self.config.aws_profile,
            "--query", f"CertificateSummaryList[?DomainName=='{self.config.api_domain_name}'].CertificateArn",
            "--output", "json",
        ], show_output=False)
        if result.returncode != 0:
            return False, [], []
        try:
            arns = json.loads(result.stdout or "[]") or []
        except json.JSONDecodeError:
            return False, [], []
        pending: tuple[bool, list[str], list[dict]] = (False, [], [])
        for arn in arns:
            detail = self.command(self.config.aws_executable, [
                "acm", "describe-certificate", "--region", "us-east-1", "--profile", self.config.aws_profile,
                "--certificate-arn", arn, "--query", "Certificate", "--output", "json",
            ], show_output=False)
            if detail.returncode != 0:
                continue
            try:
                certificate = json.loads(detail.stdout or "{}")
            except json.JSONDecodeError:
                continue
            records = []
            for option in certificate.get("DomainValidationOptions", []):
                resource_record = option.get("ResourceRecord") or {}
                if resource_record.get("Name") and resource_record.get("Value"):
                    records.append({
                        "name": resource_record["Name"],
                        "type": resource_record.get("Type", "CNAME"),
                        "value": resource_record["Value"],
                    })
            fqdns = [record["name"] for record in records]
            info = (certificate.get("Status") == "ISSUED", fqdns, records)
            if info[0]:
                return info
            if records:
                pending = info
        return pending

    def check_lock(self) -> bool:
        if has_running_terraform():
            self.emit("A Terraform process is already running. Close or finish it before using this controller.")
            return False
        return True

    def make_tfvars(
        self,
        validation_fqdns: list[str] | None = None,
        enable_api_alias: bool = False,
    ) -> Path:
        values = {
            "ami_id": self.config.ami_id,
            "api_domain_name": self.config.api_domain_name,
            "enable_api_alias": enable_api_alias,
        }
        if validation_fqdns:
            values["api_certificate_validation_record_fqdns"] = validation_fqdns
        handle = tempfile.NamedTemporaryFile("w", suffix=".tfvars.json", delete=False, encoding="utf-8")
        json.dump(values, handle, indent=2)
        handle.write("\n")
        handle.close()
        return Path(handle.name)

    def _terraform_failure(self, operation: str, result: subprocess.CompletedProcess[str]) -> OperationResult:
        output = (result.stdout or "") + (result.stderr or "")
        if is_lock_error(output):
            message = "Terraform state is locked. Wait for the other operation; this controller will not force-unlock it."
        elif "CNAMEAlreadyExists" in output:
            message = "CloudFront could not attach api.sakaygaray.com because that alias is still assigned elsewhere."
        else:
            message = f"Terraform {operation} failed. Review the log for the exact error."
        self.emit(message)
        return OperationResult(False, message)

    def start(self) -> OperationResult:
        return self._apply(enable_custom_domain=False, enable_api_alias=False)

    def prepare_domain(self) -> OperationResult:
        outcome = self._apply(enable_custom_domain=True, enable_api_alias=False)
        if not outcome.success:
            return outcome
        conflicts = self.domain_conflicts()
        if conflicts is None:
            return OperationResult(True, "ACM certificate attached, but the CloudFront conflict check was unavailable.")
        if conflicts:
            self.emit("CloudFront domain conflicts: " + json.dumps(conflicts, separators=(",", ":")))
            return OperationResult(True, "ACM certificate attached. CloudFront domain conflict details are in the log.")
        return OperationResult(True, "ACM certificate attached; no conflicting domain was reported.")

    def apply_config(self) -> OperationResult:
        return self._apply(enable_custom_domain=True, enable_api_alias=True)

    def _apply(self, enable_custom_domain: bool, enable_api_alias: bool) -> OperationResult:
        if not self.verify_identity() or not self.check_lock():
            return OperationResult(False, "AWS identity or Terraform availability check failed.")
        if not self.check_driver_documents_bucket(required=True):
            return OperationResult(False, "Persistent driver document storage is not ready. Apply the bootstrap Terraform once.")
        validation_fqdns = []
        if enable_custom_domain:
            certificate_ready, validation_fqdns, validation_records = self.certificate_info()
            if not certificate_ready:
                self.emit(format_dns_instructions("", validation_records))
                message = "ACM is not issued yet. Add the displayed validation CNAME at Namecheap, then retry Apply Config."
                self.emit(message)
                self.status()
                return OperationResult(False, message)
        else:
            self.emit("Starting the base stack without the custom API alias. Use Prepare Domain after ACM validation is issued.")
        tfvars = self.make_tfvars(validation_fqdns, enable_api_alias=enable_api_alias)
        try:
            result = self.terraform(["apply", "-auto-approve", "-input=false", "-lock-timeout=0s", f"-var-file={tfvars}"])
            if result.returncode != 0:
                outcome = self._terraform_failure("apply", result)
                self.status()
                return outcome
            self.emit("AWS staging apply completed.")
            self.status()
            return OperationResult(True, "AWS staging apply completed.")
        finally:
            tfvars.unlink(missing_ok=True)

    def domain_conflicts(self, distribution_id: str = "") -> list[dict] | None:
        if not distribution_id:
            distribution = self.aws([
                "cloudfront", "list-distributions", "--query",
                "DistributionList.Items[?Comment=='ParaGO AWS staging API and Socket.IO'].Id | [0]",
                "--output", "text",
            ], show_output=False)
            distribution_id = distribution.stdout.strip() if distribution.returncode == 0 else ""
        if not distribution_id or distribution_id == "None":
            self.emit("CloudFront conflict check skipped: target distribution ID was unavailable.")
            return None
        result = self.aws([
            "cloudfront", "list-domain-conflicts",
            "--domain", self.config.api_domain_name,
            "--domain-control-validation-resource", f"DistributionId={distribution_id}",
            "--query", "DomainConflicts", "--output", "json",
        ], show_output=False)
        if result.returncode != 0:
            self.emit("CloudFront conflict check was unavailable. Review AWS permissions or use the AWS console.")
            return None
        try:
            return json.loads(result.stdout or "[]") or []
        except json.JSONDecodeError:
            self.emit("CloudFront conflict check returned unreadable output.")
            return None

    def destroy(self) -> OperationResult:
        if not self.verify_identity() or not self.check_lock():
            return OperationResult(False, "AWS identity or Terraform availability check failed.")
        _, validation_fqdns, _ = self.certificate_info()
        if not validation_fqdns:
            validation_fqdns = self.config.api_certificate_validation_record_fqdns
        tfvars = self.make_tfvars(validation_fqdns, enable_api_alias=False)
        try:
            result = self.terraform(["destroy", "-auto-approve", "-input=false", "-lock-timeout=0s", f"-var-file={tfvars}"])
            if result.returncode != 0:
                outcome = self._terraform_failure("destroy", result)
                self.status()
                return outcome
            self.emit("AWS staging was destroyed. MongoDB Atlas and Terraform bootstrap state were not targeted.")
            self.status()
            return OperationResult(True, "AWS staging destroy completed.")
        finally:
            tfvars.unlink(missing_ok=True)

    def status(self) -> OperationResult:
        self.emit("--- AWS status ---")
        documents_ready = self.check_driver_documents_bucket()
        ec2_summary = "unknown"
        cloudfront_summary = "unknown"
        api_summary = "unavailable"
        records = []
        distributions = []
        status_errors = []

        state = self.terraform(["state", "list"], show_output=False)
        if state.returncode == 0:
            managed_resources = [line for line in state.stdout.splitlines() if line.strip()]
            terraform_stack_exists = bool(managed_resources)
            self.emit(f"Terraform state: {len(managed_resources)} managed resource(s)")
        else:
            terraform_stack_exists = False
            status_errors.append("Terraform state")
            self.emit("Terraform state: unavailable")

        instance = self.aws([
            "ec2", "describe-instances", "--filters", "Name=tag:Name,Values=parago-staging-aws-api",
            "Name=instance-state-name,Values=pending,running,stopping,stopped",
            "--query", "Reservations[].Instances[].{Id:InstanceId,State:State.Name}", "--output", "json",
        ])
        if instance.returncode != 0:
            self.emit("EC2: status unavailable")
            status_errors.append("EC2")
        else:
            try:
                records = json.loads(instance.stdout or "[]") or []
                self.emit("EC2: " + (json.dumps(records, separators=(",", ":")) if records else "not found"))
                states = [record.get("State", "unknown") for record in records]
                ec2_summary = ", ".join(states) if states else "not found"
            except json.JSONDecodeError:
                self.emit("EC2: status unavailable")
                status_errors.append("EC2")

        distribution = self.aws([
            "cloudfront", "list-distributions", "--query",
            "DistributionList.Items[?Comment=='ParaGO AWS staging API and Socket.IO'].[DomainName,Status,Enabled,Aliases.Items,ViewerCertificate.ACMCertificateArn,Id]",
            "--output", "json",
        ])
        if distribution.returncode != 0:
            self.emit("CloudFront: status unavailable")
            status_errors.append("CloudFront")
        else:
            try:
                distributions = json.loads(distribution.stdout or "[]") or []
                self.emit("CloudFront: " + json.dumps(distributions, separators=(",", ":")))
                if distributions:
                    cloudfront_summary = ", ".join(
                        f"{item[1]}/{str(item[2]).lower()}" for item in distributions
                    )
                else:
                    cloudfront_summary = "not found"
            except json.JSONDecodeError:
                self.emit("CloudFront: status unavailable")
                status_errors.append("CloudFront")

        try:
            with urllib.request.urlopen(self.config.api_health_url, timeout=8) as response:
                self.emit(f"API health: HTTP {response.status}")
                api_summary = f"HTTP {response.status}"
        except (urllib.error.URLError, TimeoutError) as error:
            self.emit(f"API health: unavailable ({error})")
        domain_prepared = bool(distributions and distributions[0][4])
        aliases = (distributions[0][3] or []) if distributions else []
        alias_attached = self.config.api_domain_name in aliases
        conflicts = None
        if domain_prepared and not alias_attached:
            conflicts = self.domain_conflicts(str(distributions[0][5]))
            if conflicts:
                self.emit("CloudFront domain conflicts: " + json.dumps(conflicts, separators=(",", ":")))
        can_apply_config = domain_prepared and not alias_attached and conflicts == []
        if alias_attached:
            alias_summary = "attached"
        elif domain_prepared and conflicts is None:
            alias_summary = "conflict check unavailable"
        elif conflicts:
            alias_summary = "conflict"
        elif can_apply_config:
            alias_summary = "ready"
        else:
            alias_summary = "not prepared"

        dns_message = self.dns_instructions(distributions)
        stack_exists = terraform_stack_exists or bool(records) or bool(distributions)
        self.set_status(
            f"EC2: {ec2_summary}  |  CloudFront: {cloudfront_summary}  |  Alias: {alias_summary}  |  API: {api_summary}",
            stack_exists,
            any(record.get("State") == "running" for record in records),
            dns_message,
            not status_errors,
            bool(distributions),
            domain_prepared,
            can_apply_config,
        )
        self.emit(f"Admin URL: {self.config.admin_url}")
        self.emit(
            "MongoDB Atlas and driver license documents are persistent; Valkey and EC2-local data are temporary."
        )
        if not documents_ready:
            self.emit("Driver account creation remains unavailable until the bootstrap document bucket is applied.")
        if status_errors:
            return OperationResult(False, f"Status incomplete: {', '.join(status_errors)} unavailable.")
        return OperationResult(True, "AWS status refreshed.")

    def dns_instructions(self, distributions: list) -> str:
        cloudfront_domain = str(distributions[0][0]) if distributions else ""
        validation = []
        outputs = self.terraform(["output", "-json"], show_output=False)
        try:
            values = json.loads(outputs.stdout or "")
            cloudfront_domain = str(
                values.get("cloudfront_domain_name", {}).get("value") or cloudfront_domain
            )
            validation = values.get("api_certificate_validation_options", {}).get("value", []) or []
        except (json.JSONDecodeError, AttributeError):
            pass
        if not validation:
            _, _, validation = self.certificate_info()
        return format_dns_instructions(cloudfront_domain, validation)


class App:
    def __init__(self, root: Tk):
        self.root = root
        self.root.title("ParaGO AWS Staging Controller")
        self.root.geometry("900x620")
        self.events: queue.Queue[tuple[str, object]] = queue.Queue()
        self.config = ControllerConfig.load()
        self.controller = AwsController(self.config, self.emit, self.queue_status)
        self.busy = False
        self.stack_exists = False
        self.server_running = False
        self.status_reliable = False
        self.base_ready = False
        self.domain_prepared = False
        self.can_apply_config = False
        self.status_var = StringVar(value="Ready")
        self.status_detail_var = StringVar(value="Live status: waiting for first check")
        self.dns_status_var = StringVar(value="DNS updates: waiting for first check")
        self._build()
        self.root.after(100, self._drain_events)
        self.emit("Ready. AWS credentials are read from the configured AWS CLI profile; none are stored here.")
        self.emit(f"Region: {self.config.aws_region} | Profile: {self.config.aws_profile}")
        self._run("status", automatic=True)

    def _build(self) -> None:
        frame = ttk.Frame(self.root, padding=14)
        frame.pack(fill=BOTH, expand=True)
        ttk.Label(frame, text="ParaGO AWS Staging Controller", font=("Segoe UI", 18, "bold")).pack(anchor="w")
        ttk.Label(frame, text=f"API: {self.config.api_domain_name}   |   Admin: {self.config.admin_url}").pack(anchor="w", pady=(2, 12))
        buttons = ttk.Frame(frame)
        buttons.pack(fill="x", pady=(0, 10))
        self.start_button = ttk.Button(buttons, text="Start AWS", command=lambda: self._run("start"))
        self.start_button.pack(side="left", padx=(0, 8))
        self.prepare_domain_button = ttk.Button(buttons, text="Prepare Domain", command=lambda: self._run("prepare_domain"))
        self.prepare_domain_button.pack(side="left", padx=(0, 8))
        self.apply_config_button = ttk.Button(buttons, text="Apply Config", command=lambda: self._run("apply_config"))
        self.apply_config_button.pack(side="left", padx=(0, 8))
        self.destroy_button = ttk.Button(buttons, text="Destroy Staging", command=self._confirm_destroy)
        self.destroy_button.pack(side="left", padx=(0, 8))
        self.status_button = ttk.Button(buttons, text="Refresh Status", command=lambda: self._run("status"))
        self.status_button.pack(side="left", padx=(0, 8))
        ttk.Button(buttons, text="View Logs", command=self._view_logs).pack(side="left")
        ttk.Label(frame, textvariable=self.status_var).pack(anchor="w", pady=(0, 5))
        ttk.Label(frame, textvariable=self.status_detail_var, wraplength=850).pack(anchor="w", pady=(0, 8))
        dns_frame = ttk.Frame(frame)
        dns_frame.pack(fill="x", pady=(0, 8))
        self.dns_entry = ttk.Entry(dns_frame, textvariable=self.dns_status_var, state="readonly")
        self.dns_entry.pack(side="left", fill="x", expand=True)
        ttk.Button(dns_frame, text="Copy DNS", command=self._copy_dns).pack(side="left", padx=(8, 0))
        self.log = Text(frame, height=28, wrap="word", state=DISABLED, background="#111827", foreground="#e5e7eb", insertbackground="#ffffff")
        self.log.pack(fill=BOTH, expand=True)
        scrollbar = ttk.Scrollbar(self.log, orient="vertical", command=self.log.yview)
        scrollbar.pack(side="right", fill="y")
        self.log.configure(yscrollcommand=scrollbar.set)

    def emit(self, message: str) -> None:
        clean = redact_output(message)
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        with LOG_PATH.open("a", encoding="utf-8") as handle:
            handle.write(time.strftime("[%H:%M:%S] ") + clean + "\n")
        self.events.put(("log", clean))

    def queue_status(
        self,
        message: str,
        stack_exists: bool = False,
        server_running: bool = False,
        dns_message: str = "DNS updates: unavailable",
        reliable: bool = False,
        base_ready: bool = False,
        domain_prepared: bool = False,
        can_apply_config: bool = False,
    ) -> None:
        self.events.put((
            "status",
            (
                f"Live status (checked {time.strftime('%H:%M:%S')}): {message}",
                stack_exists,
                server_running,
                dns_message,
                reliable,
                base_ready,
                domain_prepared,
                can_apply_config,
            ),
        ))

    def _apply_button_state(self) -> None:
        if self.busy:
            for button in (self.start_button, self.prepare_domain_button, self.apply_config_button, self.destroy_button, self.status_button):
                button.configure(state=DISABLED)
            return
        if not self.status_reliable:
            for button in (self.start_button, self.prepare_domain_button, self.apply_config_button, self.destroy_button):
                button.configure(state=DISABLED)
            self.status_button.configure(state=NORMAL)
            return
        self.start_button.configure(state=NORMAL if not self.base_ready else DISABLED)
        self.prepare_domain_button.configure(state=NORMAL if self.base_ready and not self.domain_prepared else DISABLED)
        self.apply_config_button.configure(state=NORMAL if self.can_apply_config else DISABLED)
        self.destroy_button.configure(state=NORMAL if self.stack_exists else DISABLED)
        self.status_button.configure(state=NORMAL)

    def _drain_events(self) -> None:
        while True:
            try:
                kind, message = self.events.get_nowait()
            except queue.Empty:
                break
            if kind == "log":
                self.log.configure(state=NORMAL)
                self.log.insert(END, time.strftime("[%H:%M:%S] ") + message + "\n")
                self.log.see(END)
                self.log.configure(state=DISABLED)
            elif kind == "status":
                status_message, stack_exists, server_running, dns_message, reliable, base_ready, domain_prepared, can_apply_config = message
                self.status_detail_var.set(status_message)
                self.dns_status_var.set(dns_message)
                self.stack_exists = stack_exists
                self.server_running = server_running
                self.status_reliable = reliable
                self.base_ready = base_ready
                self.domain_prepared = domain_prepared
                self.can_apply_config = can_apply_config
                self._apply_button_state()
            elif kind == "done":
                self.busy = False
                outcome = message
                prefix = "Completed" if outcome.success else "Failed"
                self.status_var.set(f"{prefix}: {outcome.message}")
                self._apply_button_state()
        self.root.after(100, self._drain_events)

    def _run(self, operation: str, automatic: bool = False) -> None:
        if self.busy:
            return
        self.busy = True
        operation_label = {
            "start": "AWS start",
            "prepare_domain": "domain preparation",
            "apply_config": "domain configuration",
            "destroy": "staging destroy",
            "status": "status",
        }.get(operation, operation)
        self.status_var.set(f"{'Auto-checking' if automatic else 'Running'} {operation_label}...")
        self._apply_button_state()

        def worker() -> None:
            try:
                outcome = getattr(self.controller, operation)()
                if not isinstance(outcome, OperationResult):
                    outcome = OperationResult(False, f"{operation} returned no result.")
            except Exception as error:  # Keep GUI alive and expose actionable failure.
                self.emit(f"Controller error: {error}")
                outcome = OperationResult(False, f"Controller error: {error}")
            self.events.put(("done", outcome))

        threading.Thread(target=worker, daemon=True).start()

    def _confirm_destroy(self) -> None:
        confirmed = messagebox.askyesno(
            "Destroy AWS staging?",
            "This removes the disposable AWS staging resources, including EC2, Valkey, CloudFront, NAT Gateway, and related infrastructure.\n\nMongoDB Atlas, driver license documents, and Terraform bootstrap state are not targeted. Continue?",
            icon="warning",
        )
        if confirmed:
            self._run("destroy")

    def _copy_dns(self) -> None:
        self.root.clipboard_clear()
        self.root.clipboard_append(self.dns_status_var.get())
        self.status_var.set("DNS instructions copied to clipboard")

    def _view_logs(self) -> None:
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        if not LOG_PATH.exists():
            LOG_PATH.write_text("ParaGO AWS Staging Controller log\n", encoding="utf-8")
        os.startfile(LOG_PATH)  # type: ignore[attr-defined]


def main() -> None:
    app_root = Tk()
    app = App(app_root)
    app_root.mainloop()


if __name__ == "__main__":
    main()
