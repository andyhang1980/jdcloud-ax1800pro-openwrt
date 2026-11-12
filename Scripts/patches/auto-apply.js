/* WRT 定制 v2：改动不再自动保存
 * 新流程：用户改任何配置 -> 表单暂存 -> 点"保存" -> 自动接着点"应用"，一次点击写进配置并生效。
 *
 * v1 的问题：
 *   1) 监听 change 自动提交，用户每动一下就被强制保存并刷新页面；
 *   2) WiFi 改密码/SSID 走 widget 事件，未被覆盖，反而不触发保存（不一致）。
 *
 * v2 做法：
 *   - 完全移除 change 自动提交（任何控件都等用户点保存）；
 *   - 拦截"保存"按钮点击，记 sessionStorage 标志；
 *   - 若保存后页面刷新 -> 下次加载看到标志自动点"应用"；
 *   - 若保存是异步不刷新 -> 1.5 秒后直接点"应用"。
 *   两种 LuCI 保存方式都能覆盖，且 WiFi/文本/下拉/开关行为完全一致。 */
(function () {
	if (window.__wrtAutoApply) return;
	window.__wrtAutoApply = true;

	var FLAG = 'wrtPendingApply';
	var SAVE_SEL = '.cbi-page-actions input.cbi-button-save, .cbi-page-actions button.cbi-button-save, .cbi-page-actions a.cbi-button-save';
	var APPLY_SEL = '.cbi-page-actions input.cbi-button-apply, .cbi-page-actions button.cbi-button-apply, .cbi-page-actions a.cbi-button-apply';

	function q(sel) { try { return document.querySelector(sel); } catch (e) { return null; } }
	function getFlag() { try { return sessionStorage.getItem(FLAG); } catch (e) { return null; } }
	function setFlag(v) { try { sessionStorage.setItem(FLAG, v); } catch (e) {} }
	function delFlag() { try { sessionStorage.removeItem(FLAG); } catch (e) {} }

	/* 1) 页面加载：上次点了保存但没应用成功 -> 自动补一次"应用" */
	function applyIfPending() {
		if (getFlag() !== '1') return;
		delFlag();
		setTimeout(function () {
			var a = q(APPLY_SEL);
			if (a) a.click();
		}, 700);
	}

	/* 2.5) 表单是否还有校验错误（保存失败时绝不能去点"应用"，否则会丢改动） */
	function hasFormError() {
		try {
			if (document.querySelector('.cbi-value-error, input.cbi-input-invalid, .cbi-value-error-msg, [class*="invalid"]')) return true;
			var f = window.__wrtAAForm;
			if (f && f.cbi_state && f.cbi_state !== 'saved' && f.cbi_state !== 'applied') {
				/* 处于 add-section/del-section 或其他非就绪态时不自动应用 */
				if (f.cbi_state === 'add-section' || f.cbi_state === 'del-section') return true;
			}
		} catch (e) {}
		return false;
	}

	/* 2) 点"保存"：先记标志，再判断保存是否会刷新页面 */
	document.addEventListener('click', function (e) {
		var el = e.target;
		if (!el) return;
		var btn = null;
		try { btn = el.closest ? el.closest(SAVE_SEL) : null; } catch (err) { btn = null; }
		if (!btn) return;

		setFlag('1');

		/* 若 1.5 秒后页面还在（异步保存，不刷新），说明没有走完整提交，
 *           此时直接补点"应用"，实现"点保存 -> 自动写进配置并生效"。 */
		setTimeout(function () {
			if (getFlag() !== '1') return;           /* 已经被 applyIfPending 处理过 */
			if (!document.body) return;
			/* 保存没成功（表单还有错误）：丢弃标志，等用户改好后再点保存 */
			if (hasFormError()) { delFlag(); return; }
			var stillSave = q(SAVE_SEL);
			var apply = q(APPLY_SEL);
			if (stillSave && apply) {
				delFlag();
				apply.click();
			}
			/* 页面已刷新/跳转 -> 保留标志，交给下次 load 的 applyIfPending */
		}, 1500);
	}, true);

	/* 3) 页面就绪后立刻检查（同步加载的页面） */
	if (document.readyState === 'complete' || document.readyState === 'interactive') {
		setTimeout(applyIfPending, 200);
	} else {
		document.addEventListener('DOMContentLoaded', function () { setTimeout(applyIfPending, 200); });
	}
	window.addEventListener('load', function () { setTimeout(applyIfPending, 400); });
})();
