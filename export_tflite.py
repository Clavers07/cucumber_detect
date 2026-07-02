import os
import sys

def main():
    print("=" * 70)
    print("YOLOv12 to TFLite (LiteRT) Exporter via ONNX & onnx2tf")
    print("=" * 70)
    
    # 1. Check requirements
    try:
        from ultralytics import YOLO
    except ImportError:
        print("❌ Error: Package 'ultralytics' belum terinstall.")
        print("Silakan jalankan perintah berikut di Google Colab/Terminal Anda:")
        print("   pip install ultralytics onnx onnx-simplifier onnx2tf tensorflow")
        sys.exit(1)
        
    model_path = "best.pt"
    if not os.path.exists(model_path):
        if os.path.exists("assets/best.pt"):
            model_path = "assets/best.pt"
        else:
            print(f"❌ Error: File '{model_path}' tidak ditemukan di root folder.")
            print("Silakan letakkan file 'best.pt' Anda di root folder proyek ini terlebih dahulu.")
            sys.exit(1)

    print(f"📦 Menggunakan model: {model_path}")
    
    # Step 1: Export to ONNX first
    print("\n➡️ Langkah 1: Mengekspor PyTorch (.pt) ke ONNX (.onnx)...")
    try:
        model = YOLO(model_path)
        # Export ke ONNX dengan static shape (imgsz=640)
        # dynamic=False agar layout model terkunci dan onnx2tf bisa mentranspose dengan benar
        onnx_path = model.export(format="onnx", imgsz=640, dynamic=False)
        print(f"✅ ONNX berhasil dibuat: {onnx_path}")
    except Exception as e:
        print(f"❌ Gagal mengekspor ke ONNX: {e}")
        sys.exit(1)
        
    # Step 2: Convert ONNX to TFLite using onnx2tf to resolve layout / dimension issues
    print("\n➡️ Langkah 2: Mengonversi ONNX ke TFLite menggunakan onnx2tf...")
    print("   (Proses ini akan mentranspose dimensi NCHW -> NHWC dengan benar)")
    
    # Cek onnx2tf
    try:
        import subprocess
        # Jalankan onnx2tf command
        # -i input onnx
        # -o output folder
        # -nu (non-verbose/quiet)
        cmd = ["onnx2tf", "-i", onnx_path, "-o", "saved_model_onnx2tf"]
        print(f"Running command: {' '.join(cmd)}")
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"❌ Error saat menjalankan onnx2tf:\n{result.stderr}")
            print("\nAlternatif: Silakan instal versi onnx2tf terbaru:")
            print("   pip install --upgrade onnx2tf")
            sys.exit(1)
            
        print("✅ onnx2tf berhasil dijalankan!")
        
        # Cari file tflite hasil output onnx2tf
        # Biasanya ditaruh di saved_model_onnx2tf/best_float32.tflite atau best_float16.tflite
        tflite_dir = "saved_model_onnx2tf"
        tflite_files = [f for f in os.listdir(tflite_dir) if f.endswith(".tflite")] if os.path.exists(tflite_dir) else []
        
        if not tflite_files:
            print("❌ Error: Tidak ditemukan file .tflite di dalam folder 'saved_model_onnx2tf'.")
            sys.exit(1)
            
        print("\n" + "=" * 70)
        print("🎉 BERHASIL! Model TFLite bebas bug dimensi telah dibuat:")
        for f in tflite_files:
            path = os.path.join(tflite_dir, f)
            size_mb = os.path.getsize(path) / (1024 * 1024)
            print(f"⭐ {f} ({size_mb:.2f} MB) -> {path}")
            
        print("=" * 70)
        print("\n👉 Langkah selanjutnya:")
        print("1. Ambil file tflite (misal: 'best_float32.tflite') dari folder 'saved_model_onnx2tf'")
        print("2. Pindahkan ke folder assets/ pada proyek Flutter Anda")
        print("3. Rename menjadi 'best_float16.tflite'")
        print("4. Jalankan aplikasi Flutter Anda!")
        
    except ImportError:
        print("❌ Error: 'onnx2tf' tidak ditemukan.")
        print("Jalankan perintah ini di Colab Anda untuk menginstalnya:")
        print("   pip install onnx2tf tensorflow-cpu onnx-simplifier")
    except Exception as e:
        print(f"❌ Terjadi kesalahan pada Langkah 2: {e}")

if __name__ == "__main__":
    main()

