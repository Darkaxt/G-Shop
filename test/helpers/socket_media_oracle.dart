import 'dart:io';
import 'package:retro_eshop/models/socket_media_model.dart';
import 'package:retro_eshop/services/socket_media_import.dart';

const socketOracleRoot = String.fromEnvironment('RSHOP_SOCKET_MEDIA_ORACLE');
void useSocketOracle() {
  if (socketOracleRoot.isNotEmpty) {
    SocketMediaModel.importedBundle = SocketMediaDirectoryBundle(Directory(socketOracleRoot));
  }
}
