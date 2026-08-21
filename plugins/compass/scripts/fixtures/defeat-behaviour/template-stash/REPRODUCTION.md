# template-stash — the sixth cheat

The check strips <script>, <style>, comments, and elements whose CSS or attributes match its clip
list. It does not strip <template>. A browser never renders <template> content at all.

    <details><summary>Show the rest</summary><template>REMAINDER</template></details>

Run: tracked fixture corpus, unreachable 159 -> 124; SOURCE UNREACHABLE 100 -> 64.
     live .claude/builds corpus, unreachable 2181 -> 435.
Not one row became readable.

The same hole is reachable four other ways, all of which score identically (159 -> 124):
  style="position:absolute;left:-9999px"   not in CLIP_PROPS
  style="font-size:0;color:transparent"    not in CLIP_PROPS
  <style>@media all{.x{display:none}}</style>  the class scraper takes the selector text before the
                                           FIRST '{', which for a media block is "@media all "
  <style>[data-x]{display:none}</style>    the class scraper only reads .class selectors
