(function () {
  var currentMarkdown = "";
  var selectionChangeToken = 0;

  function post(message) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.factoryEditor) {
      window.webkit.messageHandlers.factoryEditor.postMessage(message);
    }
  }

  function escapeHtml(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  function inlineMarkdownToHtml(value) {
    return escapeHtml(value)
      .replace(/`([^`]+)`/g, "<code>$1</code>")
      .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
      .replace(/\*([^*]+)\*/g, "<em>$1</em>")
      .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>');
  }

  function markdownToHtml(markdown) {
    var lines = String(markdown || "").split(/\r?\n/);
    var html = [];
    var list = null;

    function closeList() {
      if (list) {
        html.push("</" + list + ">");
        list = null;
      }
    }

    lines.forEach(function (line) {
      var trimmed = line.trim();
      var heading = trimmed.match(/^(#{1,6})\s+(.+)$/);
      var bullet = trimmed.match(/^[-*]\s+(.+)$/);
      var number = trimmed.match(/^\d+\.\s+(.+)$/);
      var quote = trimmed.match(/^>\s?(.+)$/);

      if (!trimmed) {
        closeList();
        return;
      }

      if (heading) {
        closeList();
        html.push("<h" + heading[1].length + ">" + inlineMarkdownToHtml(heading[2]) + "</h" + heading[1].length + ">");
      } else if (bullet) {
        if (list !== "ul") {
          closeList();
          html.push("<ul>");
          list = "ul";
        }
        html.push("<li>" + inlineMarkdownToHtml(bullet[1]) + "</li>");
      } else if (number) {
        if (list !== "ol") {
          closeList();
          html.push("<ol>");
          list = "ol";
        }
        html.push("<li>" + inlineMarkdownToHtml(number[1]) + "</li>");
      } else if (quote) {
        closeList();
        html.push("<blockquote><p>" + inlineMarkdownToHtml(quote[1]) + "</p></blockquote>");
      } else {
        closeList();
        html.push("<p>" + inlineMarkdownToHtml(line) + "</p>");
      }
    });

    closeList();
    return html.join("\n");
  }

  function inlineHtmlToMarkdown(node) {
    if (node.nodeType === Node.TEXT_NODE) {
      return node.nodeValue || "";
    }
    if (node.nodeType !== Node.ELEMENT_NODE) {
      return "";
    }

    var tag = node.tagName.toLowerCase();
    var text = Array.from(node.childNodes).map(inlineHtmlToMarkdown).join("");

    if (tag === "strong" || tag === "b") {
      return "**" + text + "**";
    }
    if (tag === "em" || tag === "i") {
      return "*" + text + "*";
    }
    if (tag === "code") {
      return "`" + text + "`";
    }
    if (tag === "a") {
      return "[" + text + "](" + (node.getAttribute("href") || "") + ")";
    }
    if (tag === "br") {
      return "\n";
    }
    return text;
  }

  function blockToMarkdown(node) {
    if (node.nodeType === Node.TEXT_NODE) {
      return (node.nodeValue || "").trim();
    }
    if (node.nodeType !== Node.ELEMENT_NODE) {
      return "";
    }

    var tag = node.tagName.toLowerCase();
    if (/^h[1-6]$/.test(tag)) {
      return "#".repeat(parseInt(tag.substring(1), 10)) + " " + inlineHtmlToMarkdown(node).trim();
    }
    if (tag === "ul") {
      return Array.from(node.children).map(function (item) {
        return "- " + inlineHtmlToMarkdown(item).trim();
      }).join("\n");
    }
    if (tag === "ol") {
      return Array.from(node.children).map(function (item, index) {
        return (index + 1) + ". " + inlineHtmlToMarkdown(item).trim();
      }).join("\n");
    }
    if (tag === "blockquote") {
      return Array.from(node.childNodes)
        .map(blockToMarkdown)
        .join("\n")
        .split("\n")
        .map(function (line) { return "> " + line; })
        .join("\n");
    }
    if (tag === "pre") {
      return "```\n" + (node.innerText || "").trim() + "\n```";
    }
    if (tag === "p" || tag === "div") {
      return inlineHtmlToMarkdown(node).trim();
    }
    return inlineHtmlToMarkdown(node).trim();
  }

  function htmlToMarkdown(html) {
    var container = document.createElement("div");
    container.innerHTML = html || "";
    return Array.from(container.childNodes)
      .map(blockToMarkdown)
      .map(function (part) { return part.trim(); })
      .filter(Boolean)
      .join("\n\n");
  }

  function selectedText(editor) {
    return editor.selection ? editor.selection.getContent({ format: "text" }) : "";
  }

  function selectionRange(editor) {
    if (!editor.selection) { return null; }
    return editor.selection.getRng() || null;
  }

  function cursorAtInsertionPoint(editor) {
    var range = selectionRange(editor);
    return !!(range && range.collapsed);
  }

  function blockNodeForSelection(editor) {
    if (!editor.selection) { return null; }
    var node = editor.selection.getNode();
    if (!node) { return null; }
    if (node.nodeType === Node.TEXT_NODE) {
      node = node.parentNode;
    }
    while (node && node !== editor.getBody()) {
      var tag = node.tagName ? node.tagName.toLowerCase() : "";
      if (/^(p|div|li|h1|h2|h3|h4|h5|h6|blockquote|pre|ul|ol)$/.test(tag)) {
        return node;
      }
      node = node.parentNode;
    }
    return editor.getBody();
  }

  function normalizeSectionName(value) {
    var trimmed = String(value || "").trim().toLowerCase();
    if (trimmed === "goal") { return "goal"; }
    if (trimmed === "context") { return "context"; }
    if (trimmed === "scoping") { return "scoping"; }
    if (trimmed === "acceptance criteria" || trimmed === "acceptance") { return "acceptanceCriteria"; }
    return null;
  }

  function activeSection(editor) {
    var block = blockNodeForSelection(editor);
    if (!block) { return null; }

    var node = block;
    while (node && node !== editor.getBody()) {
      if (node.tagName && /^h[1-6]$/i.test(node.tagName)) {
        return normalizeSectionName(node.textContent);
      }
      node = node.previousSibling;
    }

    while (block && block.parentNode && block.parentNode !== editor.getBody()) {
      block = block.parentNode;
      var sibling = block.previousSibling;
      while (sibling) {
        if (sibling.tagName && /^h[1-6]$/i.test(sibling.tagName)) {
          return normalizeSectionName(sibling.textContent);
        }
        sibling = sibling.previousSibling;
      }
    }

    return null;
  }

  function postSelectionState(editor, eventName) {
    selectionChangeToken += 1;
    post({
      event: eventName || "selection",
      markdown: currentMarkdown,
      selectedText: selectedText(editor),
      isFocused: editor.hasFocus(),
      activeSection: activeSection(editor),
      cursorAtInsertionPoint: cursorAtInsertionPoint(editor),
      changeToken: selectionChangeToken
    });
  }

  function postChange(editor) {
    currentMarkdown = htmlToMarkdown(editor.getContent());
    postSelectionState(editor, "change");
  }

  function scheduleChange(editor) {
    postChange(editor);
    window.setTimeout(function () {
      updateInlineAI(editor);
    }, 0);
  }

  function insertSection(editor, heading, body) {
    var markdown = currentMarkdown || htmlToMarkdown(editor.getContent());
    var marker = "## " + heading;
    if (markdown.toLowerCase().indexOf(marker.toLowerCase()) !== -1) {
      editor.focus();
      return;
    }
    var separator = markdown.trim() ? "\n\n" : "";
    markdown = markdown + separator + marker + "\n" + body;
    window.FactoryEditor.setMarkdown(markdown);
    editor.focus();
  }

  function firstUsefulRect(rectList) {
    if (!rectList || !rectList.length) { return null; }
    for (var index = rectList.length - 1; index >= 0; index -= 1) {
      var rect = rectList[index];
      if (rect && (rect.width > 0 || rect.height > 0)) {
        return rect;
      }
    }
    return rectList[0] || null;
  }

  function editorFrameRect(editor) {
    var frame = editor.iframeElement;
    if (!frame && editor.getContentAreaContainer) {
      frame = editor.getContentAreaContainer().querySelector("iframe");
    }
    return frame ? frame.getBoundingClientRect() : { top: 0, left: 0, width: 0, height: 0 };
  }

  function viewportRectToPage(editor, rect) {
    if (!rect) { return null; }
    var frameRect = editorFrameRect(editor);
    return {
      top: frameRect.top + window.scrollY + rect.top,
      left: frameRect.left + window.scrollX + rect.left,
      width: rect.width,
      height: rect.height,
      bottom: frameRect.top + window.scrollY + rect.bottom,
      right: frameRect.left + window.scrollX + rect.right
    };
  }

  function selectionRect(editor) {
    var range = selectionRange(editor);
    if (!range || range.collapsed) { return null; }
    var rect = firstUsefulRect(range.getClientRects()) || range.getBoundingClientRect();
    return viewportRectToPage(editor, rect);
  }

  function caretRect(editor) {
    var range = selectionRange(editor);
    if (!range || !range.collapsed) { return null; }

    var directRect = firstUsefulRect(range.getClientRects()) || range.getBoundingClientRect();
    if (directRect && (directRect.width > 0 || directRect.height > 0)) {
      return viewportRectToPage(editor, directRect);
    }

    var marker = editor.getDoc().createElement("span");
    marker.className = "factory-inline-ai-caret";
    marker.textContent = "\u200b";

    var markerRange = range.cloneRange();
    markerRange.insertNode(marker);
    var rect = marker.getBoundingClientRect();
    marker.parentNode.removeChild(marker);
    editor.selection.setRng(range);
    return viewportRectToPage(editor, rect);
  }

  function blockRect(editor) {
    var block = blockNodeForSelection(editor);
    if (!block || !block.getBoundingClientRect) { return null; }
    return viewportRectToPage(editor, block.getBoundingClientRect());
  }

  function isEmptyInsertionContext(editor) {
    if (!cursorAtInsertionPoint(editor) || selectedText(editor).trim()) {
      return false;
    }
    var block = blockNodeForSelection(editor);
    if (!block) { return false; }
    var tag = block.tagName ? block.tagName.toLowerCase() : "";
    if (!/^(p|div|li|blockquote)$/.test(tag)) {
      return false;
    }
    return !String(block.textContent || "").replace(/\u200b/g, "").trim();
  }

  function createInlineActionButton(doc, label, action, className) {
    var button = doc.createElement("button");
    button.type = "button";
    button.className = className;
    button.textContent = label;
    button.addEventListener("mousedown", function (event) {
      event.preventDefault();
      event.stopPropagation();
    });
    button.addEventListener("click", function (event) {
      event.preventDefault();
      event.stopPropagation();
      post({ event: "inlineAIAction", action: action });
    });
    return button;
  }

  function ensureInlineAI(editor) {
    if (editor.factoryInlineAI) {
      return editor.factoryInlineAI;
    }

    var root = document.createElement("div");
    root.className = "factory-inline-ai";
    root.setAttribute("aria-hidden", "true");
    root.style.display = "none";

    var pill = createInlineActionButton(document, "+ Ask AI to write here", "ask_ai", "factory-inline-ai-pill");
    var menu = document.createElement("div");
    menu.className = "factory-inline-ai-menu";
    menu.appendChild(createInlineActionButton(document, "Rewrite", "rewrite_selection", "factory-inline-ai-chip"));
    menu.appendChild(createInlineActionButton(document, "Make clearer", "make_clearer", "factory-inline-ai-chip"));
    menu.appendChild(createInlineActionButton(document, "Shorter", "make_shorter", "factory-inline-ai-chip"));
    menu.appendChild(createInlineActionButton(document, "Ask AI", "ask_ai", "factory-inline-ai-chip factory-inline-ai-chip-primary"));

    root.appendChild(pill);
    root.appendChild(menu);
    document.body.appendChild(root);

    editor.factoryInlineAI = {
      root: root,
      pill: pill,
      menu: menu
    };
    return editor.factoryInlineAI;
  }

  function hideInlineAI(editor) {
    var inlineAI = ensureInlineAI(editor);
    inlineAI.root.style.display = "none";
    inlineAI.root.setAttribute("aria-hidden", "true");
    inlineAI.root.classList.remove("factory-inline-ai-selection");
    inlineAI.root.classList.remove("factory-inline-ai-cursor");
  }

  function showInlineAI(editor, mode, rect) {
    if (!rect) {
      hideInlineAI(editor);
      return;
    }

    var inlineAI = ensureInlineAI(editor);
    inlineAI.root.style.display = "block";
    inlineAI.root.setAttribute("aria-hidden", "false");
    inlineAI.root.classList.toggle("factory-inline-ai-selection", mode === "selection");
    inlineAI.root.classList.toggle("factory-inline-ai-cursor", mode === "cursor");
    inlineAI.pill.style.display = mode === "cursor" ? "inline-flex" : "none";
    inlineAI.menu.style.display = mode === "selection" ? "inline-flex" : "none";

    var top = mode === "selection"
      ? rect.top - 40
      : rect.top + Math.max(rect.height, 22) + 8;
    var left = mode === "selection"
      ? rect.left + Math.max(rect.width / 2, 0)
      : rect.left + 2;

    inlineAI.root.style.top = Math.max(top, 12) + "px";
    inlineAI.root.style.left = Math.max(left, 12) + "px";
  }

  function updateInlineAI(editor) {
    if (!editor || editor.removed || !editor.hasFocus()) {
      if (editor && editor.factoryInlineAI) {
        hideInlineAI(editor);
      }
      return;
    }

    var selection = selectedText(editor).trim();
    if (selection) {
      showInlineAI(editor, "selection", selectionRect(editor));
      return;
    }

    if (isEmptyInsertionContext(editor)) {
      showInlineAI(editor, "cursor", caretRect(editor) || blockRect(editor));
      return;
    }

    hideInlineAI(editor);
  }

  window.FactoryEditor = {
    setMarkdown: function (markdown) {
      currentMarkdown = String(markdown || "");
      var editor = tinymce.get("factory-editor");
      if (editor) {
        editor.setContent(markdownToHtml(currentMarkdown));
        window.setTimeout(function () {
          updateInlineAI(editor);
        }, 0);
      }
    },
    getMarkdown: function () {
      var editor = tinymce.get("factory-editor");
      return editor ? htmlToMarkdown(editor.getContent()) : currentMarkdown;
    },
    insertMarkdown: function (markdown) {
      var editor = tinymce.get("factory-editor");
      if (!editor) { return; }
      editor.insertContent(markdownToHtml(markdown));
      postChange(editor);
      updateInlineAI(editor);
    }
  };

  tinymce.init({
    selector: "#factory-editor",
    license_key: "gpl",
    base_url: "tinymce",
    suffix: ".min",
    promotion: false,
    branding: false,
    menubar: false,
    statusbar: true,
    resize: false,
    height: "100%",
    skin: "oxide",
    content_css: "default",
    content_style: [
      "body { font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif; }",
      ".factory-inline-ai-caret { display: inline-block; width: 1px; overflow: hidden; }"
    ].join("\n"),
    plugins: "advlist autolink code link lists preview quickbars searchreplace wordcount",
    toolbar: "undo redo | blocks | bold italic blockquote code | bullist numlist | link searchreplace | insertGoal insertContext insertScoping insertAcceptance | preview code",
    quickbars_selection_toolbar: "bold italic | quicklink blockquote",
    setup: function (editor) {
      editor.ui.registry.addButton("insertGoal", {
        text: "Goal",
        tooltip: "Insert Goal section",
        onAction: function () {
          insertSection(editor, "Goal", "Define the outcome in one sentence.");
        }
      });
      editor.ui.registry.addButton("insertContext", {
        text: "Context",
        tooltip: "Insert Context section",
        onAction: function () {
          insertSection(editor, "Context", "What changed, what exists today, and why this matters.");
        }
      });
      editor.ui.registry.addButton("insertScoping", {
        text: "Scoping",
        tooltip: "Insert Scoping section",
        onAction: function () {
          insertSection(editor, "Scoping", "In scope:\n- \n\nOut of scope:\n- ");
        }
      });
      editor.ui.registry.addButton("insertAcceptance", {
        text: "Acceptance",
        tooltip: "Insert Acceptance Criteria section",
        onAction: function () {
          insertSection(editor, "Acceptance Criteria", "- User-facing behavior is clear and task-centered.\n- Changes are verified with the relevant local checks.");
        }
      });
      editor.on("input change undo redo keyup SetContent", function () {
        scheduleChange(editor);
      });
      editor.on("NodeChange SelectionChange", function () {
        postSelectionState(editor, "selection");
        updateInlineAI(editor);
      });
      editor.on("focus", function () {
        postSelectionState(editor, "focus");
        updateInlineAI(editor);
      });
      editor.on("blur", function () {
        postSelectionState(editor, "blur");
        hideInlineAI(editor);
      });
      editor.on("keydown", function (event) {
        if (event.key === "Escape") {
          hideInlineAI(editor);
          post({ event: "dismissInlineAI" });
        }
        if ((event.metaKey || event.ctrlKey) && String(event.key).toLowerCase() === "k") {
          event.preventDefault();
          post({ event: "openInlineAI" });
        }
      });
      editor.on("ScrollContent", function () {
        updateInlineAI(editor);
      });
      editor.on("remove", function () {
        if (editor.factoryInlineAI && editor.factoryInlineAI.root.parentNode) {
          editor.factoryInlineAI.root.parentNode.removeChild(editor.factoryInlineAI.root);
        }
      });
    },
    init_instance_callback: function (editor) {
      editor.getWin().addEventListener("scroll", function () {
        updateInlineAI(editor);
      });
      post({ event: "ready", markdown: currentMarkdown, selectedText: "" });
      window.setTimeout(function () {
        postSelectionState(editor, "selection");
        updateInlineAI(editor);
      }, 0);
    }
  });
})();
