import starlight from '@astrojs/starlight';
import { defineConfig } from 'astro/config';

// https://astro.build/config
export default defineConfig({
  site: 'https://ajmalbuv.github.io',
  base: '/typst_flutter',
  integrations: [
    starlight({
      title: 'typst_flutter',
      customCss: ['./src/styles/custom.css'],
      social: [
        {
          icon: 'github',
          label: 'GitHub',
          href: 'https://github.com/ajmalbuv/typst_flutter',
        },
      ],
      sidebar: [
        {
          label: 'Start Here',
          items: [
            { label: 'Introduction', slug: 'index' },
            { label: 'Getting Started', slug: 'guides/getting-started' },
          ],
        },
        {
          label: 'Reference',
          items: [{ label: 'API & Widgets', slug: 'reference/api' }],
        },
        {
          label: 'External Links',
          items: [
            {
              label: 'pub.dev Package',
              link: 'https://pub.dev/packages/typst_flutter',
            },
            {
              label: 'API Documentation',
              link: 'https://pub.dev/documentation/typst_flutter/latest/',
            },
          ],
        },
      ],
    }),
  ],
});
