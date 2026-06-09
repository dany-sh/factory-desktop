(function () {
  var currentMarkdown = "";
  var changeTimer = null;

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

  function postChange(editor) {
    currentMarkdown = htmlToMarkdown(editor.getContent());
    post({
      event: "change",
      markdown: currentMarkdown,
      selectedText: selectedText(editor)
    });
  }

  function scheduleChange(editor) {
    window.clearTimeout(changeTimer);
    changeTimer = window.setTimeout(function () {
      postChange(editor);
    }, 120);
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

  window.FactoryEditor = {
    setMarkdown: function (markdown) {
      currentMarkdown = String(markdown || "");
      var editor = tinymce.get("factory-editor");
      if (editor) {
        editor.setContent(markdownToHtml(currentMarkdown));
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
    plugins: "advlist autolink autoresize code link lists preview quickbars searchreplace wordcount",
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
        post({
          event: "selection",
          markdown: currentMarkdown,
          selectedText: selectedText(editor)
        });
      });
    },
    init_instance_callback: function (editor) {
      post({ event: "ready", markdown: currentMarkdown, selectedText: "" });
      window.setTimeout(function () {
        postChange(editor);
      }, 0);
    }
  });
})();
