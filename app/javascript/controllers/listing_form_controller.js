import { Controller } from "@hotwired/stimulus"

// Sell form behaviour: category Turbo Frame reloading, title counter, photo
// picker with previews and validation (count/type/size), seller-tag limit.
// Spec fields themselves are server-rendered (sell/category_fields views).
export default class extends Controller {
  static targets = [
    "rootSelect",
    "specFrame",
    "fileInput",
    "dropzone",
    "previews",
    "photoError",
    "titleInput",
    "titleCounter",
    "tagGroup",
    "tagError",
  ]

  static values = {
    categoryFieldsBase: { type: String, default: "" },
    maxPhotos: { type: Number, default: 12 },
    maxBytes: { type: Number, default: 10485760 },
    accept: { type: String, default: "image/png,image/jpeg,image/webp" },
    maxTags: { type: Number, default: 5 },
    titleMax: { type: Number, default: 120 },
    msgTooMany: { type: String, default: "Too many photos" },
    msgType: { type: String, default: "Unsupported file type" },
    msgTooBig: { type: String, default: "File too large" },
    msgTags: { type: String, default: "Too many tags" },
    msgRemove: { type: String, default: "Remove" },
  }

  connect() {
    this.pendingFiles = []
  }

  // ----- Category picker (server-rendered spec fields) -----

  rootChanged() {
    this.reloadSpecFrame(this.rootSelectTarget.value)
  }

  childChanged(event) {
    this.reloadSpecFrame(event.target.value)
  }

  reloadSpecFrame(slug) {
    if (!this.hasSpecFrameTarget || !this.categoryFieldsBaseValue) return
    if (!slug) {
      this.specFrameTarget.innerHTML = ""
      return
    }
    this.specFrameTarget.src = this.categoryFieldsBaseValue + encodeURIComponent(slug)
  }

  // ----- Title counter -----

  updateCounter() {
    if (!this.hasTitleInputTarget || !this.hasTitleCounterTarget) return
    const count = this.titleInputTarget.value.length
    this.titleCounterTarget.textContent = `${count}/${this.titleMaxValue}`
    this.titleCounterTarget.classList.toggle(
      "text-red-600",
      count > this.titleMaxValue || count < 5,
    )
  }

  // ----- Photos -----

  openPicker() {
    this.fileInputTarget.click()
  }

  filesChanged() {
    this.pendingFiles = [...(this.fileInputTarget.files || [])]
    this.renderPreviews()
  }

  dragover(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.add("border-primary")
  }

  dragleave() {
    this.dropzoneTarget.classList.remove("border-primary")
  }

  drop(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.remove("border-primary")
    const dropped = [...(event.dataTransfer?.files || [])]
    if (dropped.length === 0) return
    // FileList is read-only: rebuild the selection from the merged list.
    const dt = new DataTransfer()
    for (const file of [...this.pendingFiles, ...dropped]) dt.items.add(file)
    this.fileInputTarget.files = dt.files
    this.pendingFiles = [...this.fileInputTarget.files]
    this.renderPreviews()
  }

  // ----- Seller tags -----

  tagToggled() {
    if (!this.hasTagGroupTarget) return
    const checked = this.tagGroupTarget.querySelectorAll("input[type=checkbox]:checked")
    for (const box of this.tagGroupTarget.querySelectorAll("input[type=checkbox]")) {
      box.disabled = !box.checked && checked.length >= this.maxTagsValue
    }
    if (this.hasTagErrorTarget) {
      this.tagErrorTarget.hidden = checked.length <= this.maxTagsValue
      this.tagErrorTarget.textContent = this.msgTagsValue
    }
  }

  // ----- Internals -----

  existingCount() {
    return [
      ...this.element.querySelectorAll('input[type=checkbox][name="listing[remove_photo_ids][]"]'),
    ].filter((box) => !box.checked).length
  }

  renderPreviews() {
    if (!this.hasPreviewsTarget) return
    const allowedTypes = this.acceptValue.split(",")
    const errors = []
    const accepted = []
    let slots = this.maxPhotosValue - this.existingCount()

    for (const file of this.pendingFiles) {
      if (!allowedTypes.includes(file.type)) {
        errors.push(`${file.name}: ${this.msgTypeValue}`)
        continue
      }
      if (file.size > this.maxBytesValue) {
        errors.push(`${file.name}: ${this.msgTooBigValue}`)
        continue
      }
      if (slots <= 0) {
        errors.push(this.msgTooManyValue)
        break
      }
      slots -= 1
      accepted.push(file)
    }

    const transfer = new DataTransfer()
    for (const file of accepted) transfer.items.add(file)
    this.fileInputTarget.files = transfer.files
    this.pendingFiles = accepted

    for (const node of this.previewsTarget.querySelectorAll("[data-pending-preview]")) {
      node.remove()
    }
    accepted.forEach((file) => {
      const li = document.createElement("li")
      li.dataset.pendingPreview = "true"
      li.className = "rounded-lg border border-border p-2"
      const box = document.createElement("div")
      box.className = "aspect-square overflow-hidden rounded-md bg-surface-muted"
      const img = document.createElement("img")
      img.src = URL.createObjectURL(file)
      img.alt = file.name
      img.className = "h-full w-full object-cover"
      box.append(img)
      li.append(box)

      const remove = document.createElement("button")
      remove.type = "button"
      remove.className =
        "mt-2 block min-h-9 w-full text-left text-xs text-muted hover:text-red-600"
      remove.textContent = this.msgRemoveValue
      remove.addEventListener("click", () => {
        const idx = accepted.indexOf(file)
        if (idx >= 0) accepted.splice(idx, 1)
        this.pendingFiles = accepted
        const next = new DataTransfer()
        for (const f of accepted) next.items.add(f)
        this.fileInputTarget.files = next.files
        this.renderPreviews()
      })
      li.append(remove)
      this.previewsTarget.append(li)
    })

    if (this.hasPhotoErrorTarget) {
      this.photoErrorTarget.hidden = errors.length === 0
      this.photoErrorTarget.textContent = errors.join(" · ")
    }
  }
}
