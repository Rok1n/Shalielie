"use strict";
const form = document.getElementById("form");
const photo = document.getElementById("photo");
const video = document.getElementById("video");
const token = document.getElementById("token");
const status = document.getElementById("status");
const submit = document.getElementById("submit");
const download = document.getElementById("download");
const downloadLink = document.getElementById("downloadLink");
let previousUrl = null;

function releasePrevious() {
  if (previousUrl) {
    URL.revokeObjectURL(previousUrl);
    previousUrl = null;
  }
}
function selectedName() {
  const stem = (photo.files[0]?.name || "photo").replace(/\.[^.]+$/, "");
  return stem.replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 64) || "photo";
}
form.addEventListener("submit", async (event) => {
  event.preventDefault();
  releasePrevious();
  download.hidden = true;
  if (!photo.files.length) {
    status.textContent = "请先选择原始 HEIC。";
    return;
  }
  if (token.value.trim().length < 24) {
    status.textContent = "请输入部署时设置的完整访问令牌（至少 24 个字符）。";
    return;
  }
  const data = new FormData();
  data.append("photo", photo.files[0], photo.files[0].name);
  if (video.files.length) data.append("video", video.files[0], video.files[0].name);
  submit.disabled = true;
  status.textContent = "正在上传并处理。处理完成后浏览器将下载文件，请保持页面打开。";
  try {
    const response = await fetch("/api/patch", {
      method: "POST",
      body: data,
      headers: { Authorization: "Bearer " + token.value.trim() },
      cache: "no-store"
    });
    if (!response.ok) {
      const message = await response.json().catch(() => ({}));
      throw new Error(message.detail || ("HTTP " + response.status));
    }
    const result = await response.blob();
    if (!result.size) throw new Error("NAS 未返回文件。");
    const name = selectedName() + "_Shalielie" + (video.files.length ? ".zip" : ".HEIC");
    previousUrl = URL.createObjectURL(result);
    downloadLink.href = previousUrl;
    downloadLink.download = name;
    download.hidden = false;
    downloadLink.click();
    status.textContent = "处理完成，下载文件为 " + name + "。若 iPhone 没有自动下载，请点击下方链接并保存到「文件」。";
  } catch (error) {
    status.textContent = "处理失败：" + error.message;
  } finally {
    submit.disabled = false;
  }
});
window.addEventListener("pagehide", releasePrevious);
