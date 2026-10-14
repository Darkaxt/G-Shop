import hashlib
import struct
import unittest

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms
from cryptography.hazmat.decrepit.ciphers.modes import CFB

from socket_resources import Reader, decrypt_resource, decompress_resource


class SocketResourceTests(unittest.TestCase):
    def test_scene_integer_vectors_preserve_signed_components(self):
        # Main SubViewport sizes use Godot's binary Vector2i tag, not Vector2.
        for kind, values in [(45, [1920, -1080]), (46, [-1, 2, 3, 4]),
                             (47, [1, -2, 3]), (51, [1, 2, -3, 4])]:
            with self.subTest(kind=kind):
                reader = Reader(struct.pack('<I' + 'i' * len(values), kind, *values))
                self.assertEqual(reader.variant(), {'variant': kind, 'values': values})
                self.assertEqual(reader.pos, len(reader.data))

    def test_envelope_preserves_exact_bytes_and_rejects_corruption(self):
        key, iv = bytes(range(32)), bytes(range(16))
        content = b'RSRC exact source geometry'
        padded = content + bytes((-len(content)) % 16)
        encrypted = Cipher(algorithms.AES(key), CFB(iv)).encryptor().update(padded)
        envelope = hashlib.md5(content).digest() + struct.pack('<Q', len(content)) + iv + encrypted
        self.assertEqual(decrypt_resource(envelope, key), content)
        corrupt = bytearray(envelope)
        corrupt[-16] ^= 1
        with self.assertRaises(ValueError):
            decrypt_resource(bytes(corrupt), key)

    def test_resource_packed_bytes_are_not_replaced_by_hashes(self):
        payload = bytes([1, 2, 3, 4, 5])
        reader = Reader(struct.pack('<II', 31, len(payload)) + payload + bytes(3))
        self.assertEqual(reader.variant(), payload)
        self.assertEqual(reader.pos, len(reader.data))

    def test_compressed_resource_keeps_original_offsets(self):
        from compression import zstd
        data = b'\0' * 32 + b'geometry'
        block = zstd.compress(data)
        envelope = b'RSCC' + struct.pack('<IIII', 2, 4096, len(data), len(block)) + block
        self.assertEqual(decompress_resource(envelope), (data, 0))


if __name__ == '__main__':
    unittest.main()
