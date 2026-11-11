import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { LexiMathSyntax } from '../main/ets/core/LexiMathSyntax';
import { MarkdownEngine } from '../main/ets/core/MarkdownEngine';

export default function localUnitTest() {
  describe('localUnitTest', () => {
    beforeAll(() => {});
    beforeEach(() => {});
    afterEach(() => {});
    afterAll(() => {});

    it('parses_spaced_inline_math_and_skips_currency', 0, () => {
      const spaced = LexiMathSyntax.inlineTokens('行内公式 $ \\frac{1}{2} + x_i $ 正常识别');
      expect(spaced.length).assertEqual(1);
      expect(spaced[0].text).assertEqual('\\frac{1}{2} + x_i');

      const mixed = LexiMathSyntax.inlineTokens('价格是$5，而公式是$x = 1$');
      expect(mixed.length).assertEqual(1);
      expect(mixed[0].text).assertEqual('x = 1');
    });

    it('parses_nested_dollar_in_text_and_raw_environments', 0, () => {
      const nested = LexiMathSyntax.inlineTokens('$\\text{当 $x > 0$ 时 } f(x) = x^2$');
      expect(nested.length).assertEqual(1);
      expect(nested[0].text).assertEqual('\\text{当 $x > 0$ 时 } f(x) = x^2');

      const rawEnvLines: string[] = [
        '\\begin{align*}',
        'a &= b + c \\\\',
        'd &= e + f',
        '\\end{align*}'
      ];
      const display = LexiMathSyntax.displayBlock(rawEnvLines, 0);
      expect(display !== undefined).assertTrue();
      expect(display?.endLine).assertEqual(3);
    });

    it('parses_math_fences_and_multiline_quotes', 0, () => {
      const md = [
        '```math',
        '\\int_0^\\infty e^{-x^2} \\dd{x} = \\frac{\\sqrt{\\pi}}{2}',
        '```',
        '',
        '> 引用推导：',
        '> $$',
        '> E = mc^2',
        '> $$'
      ].join('\n');
      const blocks = MarkdownEngine.parseBlocks(md);
      expect(blocks.length).assertEqual(2);
      expect(blocks[0].kind).assertEqual('formula');
      expect(blocks[1].kind).assertEqual('quote');
      expect(LexiMathSyntax.hasMath(blocks[1].text)).assertTrue();
    });
  });
}