import matplotlib.pyplot as plt
import numpy as np

# 生成模拟数据 (模仿原图趋势)
x = np.linspace(0, 1400, 20)
y = 1000 + 1.5 * x + np.random.normal(0, 50, 20)

# 绘图设置 (复刻原图风格)
plt.figure(figsize=(8, 6))
plt.plot(x, y, color='purple', marker='o', linestyle='-')
plt.title('RSS Memory Usage Over Time (in MB)')
plt.xlabel('Time (minutes)')
plt.ylabel('Memory Usage (MB)')
plt.grid(True, linestyle='--', alpha=0.7)
plt.xlim(0, 1600)
plt.ylim(500, 3500)

# 直接展示 (macOS 会弹出带工具栏的窗口)
plt.show()
