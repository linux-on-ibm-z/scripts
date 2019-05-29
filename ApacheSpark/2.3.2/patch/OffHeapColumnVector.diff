--- patch/spark/sql/core/src/main/java/org/apache/spark/sql/execution/vectorized/OffHeapColumnVector.java.orig  2019-05-17 05:07:38.601837000 +0000
+++ sql/core/src/main/java/org/apache/spark/sql/execution/vectorized/OffHeapColumnVector.java   2019-05-17 04:57:31.351837000 +0000
@@ -417,7 +417,7 @@
       Platform.copyMemory(src, Platform.BYTE_ARRAY_OFFSET + srcIndex,
           null, data + rowId * 4L, count * 4L);
     } else {
-      ByteBuffer bb = ByteBuffer.wrap(src).order(ByteOrder.LITTLE_ENDIAN);
+      ByteBuffer bb = ByteBuffer.wrap(src).order(ByteOrder.BIG_ENDIAN);
       long offset = data + 4L * rowId;
       for (int i = 0; i < count; ++i, offset += 4) {
         Platform.putFloat(null, offset, bb.getFloat(srcIndex + (4 * i)));
@@ -472,7 +472,7 @@
       Platform.copyMemory(src, Platform.BYTE_ARRAY_OFFSET + srcIndex,
         null, data + rowId * 8L, count * 8L);
     } else {
-      ByteBuffer bb = ByteBuffer.wrap(src).order(ByteOrder.LITTLE_ENDIAN);
+      ByteBuffer bb = ByteBuffer.wrap(src).order(ByteOrder.BIG_ENDIAN);
       long offset = data + 8L * rowId;
       for (int i = 0; i < count; ++i, offset += 8) {
         Platform.putDouble(null, offset, bb.getDouble(srcIndex + (8 * i)));
