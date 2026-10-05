import pathlib
import subprocess
import sys
import tempfile
import unittest

SCANNER = pathlib.Path(__file__).with_name("check-signing-material.py").resolve()


class SigningMaterialTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        self.add("README.md", "Synthetic fixture repository\n")

    def tearDown(self):
        self.tmp.cleanup()

    def add(self, name, content):
        p = self.root / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content)
        subprocess.run(["git", "add", "--", name], cwd=self.root, check=True)

    def scan(self):
        return subprocess.run([sys.executable, str(SCANNER)], cwd=self.root,
                              capture_output=True, text=True, timeout=10)

    def test_clean_index(self):
        self.assertEqual(self.scan().returncode, 0)

    def test_signing_extensions_even_without_pem(self):
        for suffix in ["p8", "P12", "pfx"]:
            self.add("nested/fixture." + suffix, "not a real credential")
        self.assertEqual(self.scan().returncode, 1)

    def test_private_boundaries_and_no_content_disclosure(self):
        for kind in ["", "RSA ", "EC ", "OPENSSH ", "ENCRYPTED "]:
            self.add("fixture-" + kind.strip() + ".txt",
                     "-----BEGIN " + kind + "PRIVATE KEY-----\nSYNTHETIC_SECRET_SENTINEL\n")
        result = self.scan()
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("SYNTHETIC_SECRET_SENTINEL", result.stdout + result.stderr)
        self.assertNotIn("-----BEGIN", result.stdout + result.stderr)

    def test_public_cert_and_inline_documentation_allowed(self):
        self.add("certificate.pem", "-----BEGIN CERTIFICATE-----\nsynthetic\n")
        self.add("docs.md", 'Example: "-----BEGIN ' + 'PRIVATE KEY-----" is a marker.\n')
        self.assertEqual(self.scan().returncode, 0)

    def test_untracked_operator_file_is_not_read(self):
        (self.root / "local.p8").write_text("synthetic untracked operator data")
        self.assertEqual(self.scan().returncode, 0)

    def test_scan_errors_fail_closed(self):
        with tempfile.TemporaryDirectory() as outside:
            result = subprocess.run([sys.executable, str(SCANNER)], cwd=outside,
                                    capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
