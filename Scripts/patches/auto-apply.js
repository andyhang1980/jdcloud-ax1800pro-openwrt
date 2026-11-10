/* WRT 定制：CBI 表单改动后自动"保存并应用"，不再需要手动点右上角保存
 * 机制：监听 change / widget-change / cbi-dropdown-change / cbi-dynlist-change，
 *      停止输入 1.5 秒且校验通过后，自动点击"保存并应用"（cbi_submit -> cbi.apply）。
 * 保护：弹窗内的输入不触发；已选文件的表单不触发（等手动上传）；
 *      正在输入文本时顺延；校验不通过时静默等待下一次改动。 */
(function () {
	if (window.__wrtAutoApply) return;
	window.__wrtAutoApply = true;
	var timer = null, retries = 0;
	var DELAY = 1500, MAX_RETRY = 120;
	var TEXT_TYPES = ['text', 'password', 'number', 'url', 'email', 'search', 'tel',
		'date', 'time', 'datetime-local', 'month', 'week', 'color'];

	function isTextField(el) {
		if (!el) return false;
		var t = (el.tagName || '').toLowerCase();
		if (t === 'textarea') return true;
		if (t !== 'input') return false;
		return TEXT_TYPES.indexOf((el.type || 'text').toLowerCase()) >= 0;
	}

	function formOf(el) {
		if (el.form) return el.form;
		try { return el.closest ? el.closest('form') : null; } catch (e) { return null; }
	}

	function isCbiForm(f) {
		return !!(f && f.querySelector && f.querySelector('[name^="cbid."]'));
	}

	function inModal(el) {
		try { return !!(el.closest && el.closest('[id$="-modal"]')); } catch (e) { return false; }
	}

	function validatorsPass(f) {
		if (f.cbi_state === 'add-section' || f.cbi_state === 'del-section') return false;
		var vs = f.cbi_validators;
		if (!vs) return true;
		for (var i = 0; i < vs.length; i++) {
			try { if (!vs[i]()) return false; } catch (e) {}
		}
		return true;
	}

	function busyTyping(f) {
		var a = document.activeElement;
		return !!(a && a !== document.body && f.contains && f.contains(a) && isTextField(a));
	}

	function hasSelectedFile(f) {
		var fis = f.querySelectorAll('input[type="file"]');
		for (var i = 0; i < fis.length; i++) {
			try { if (fis[i].files && fis[i].files.length) return true; } catch (e) {}
		}
		return false;
	}

	function fire() {
		timer = null;
		var f = window.__wrtAAForm;
		if (!f || !f.ownerDocument) return;
		if (busyTyping(f)) {
			if (retries++ < MAX_RETRY) timer = setTimeout(fire, DELAY);
			return;
		}
		/* 校验没过：不提交、不刷错误框，等用户改好后的下一次 change 再试 */
		if (!validatorsPass(f)) return;
		/* 已经选了文件：不自动提交，等用户点上传按钮 */
		if (hasSelectedFile(f)) return;
		var apply = f.querySelector('.cbi-page-actions input.cbi-button-apply');
		if (apply) { apply.click(); return; }
		var save = f.querySelector('.cbi-page-actions input.cbi-button-save');
		if (save) save.click();
	}

	function onChange(e) {
		var el = e.target;
		if (!el || el.type === 'file') return;
		var f = formOf(el);
		if (!isCbiForm(f)) return;
		if (inModal(el)) return;
		if (el.name && /^(cbi\.rts\.|cbi\.cts\.)/.test(el.name)) return;
		window.__wrtAAForm = f;
		retries = 0;
		if (timer) clearTimeout(timer);
		timer = setTimeout(fire, DELAY);
	}

	['change', 'widget-change', 'cbi-dropdown-change', 'cbi-dynlist-change'].forEach(function (ev) {
		document.addEventListener(ev, onChange, true);
	});
})();
